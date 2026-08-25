(* Just enough JSON reading to re-emit a contract call canonically.
   
   CosmWasm's msg field carries JSON, and the amino encoding splices it in as
   JSON rather than as a base64 string -- (amino.encoding) = "inline_json" in
   cosmwasm/wasm/v1/tx.proto. The SDK re-serialises it in the process, which
   sorts the object keys, so {"recipient":...,"amount":...} signs as
   {"amount":...,"recipient":...}.
   
   That means a signer cannot splice the caller's bytes through untouched: it
   has to parse and re-emit them the same way the SDK does, or the signature
   covers different bytes than the node computes. Hence this.
   
   It is a reader for exactly that job. Numbers are kept as their source text
   rather than parsed, because re-formatting a number is another way to change
   the bytes. *)

type value =
  | Null
  | Bool of bool
  | Number of string  (** verbatim source text *)
  | String of string
  | Array of value list
  | Object of (string * value) list

exception Bad of string

let parse (s : string) : (value, string) result =
  let n = String.length s in
  let pos = ref 0 in
  let peek () = if !pos < n then Some s.[!pos] else None in
  let fail msg = raise (Bad (Printf.sprintf "%s at byte %d" msg !pos)) in
  let advance () = incr pos in
  let skip_ws () =
    while
      !pos < n
      && match s.[!pos] with ' ' | '\t' | '\n' | '\r' -> true | _ -> false
    do
      advance ()
    done
  in
  let expect c =
    if !pos < n && s.[!pos] = c then advance ()
    else fail (Printf.sprintf "expected %C" c)
  in
  let literal word v =
    let len = String.length word in
    if !pos + len <= n && String.sub s !pos len = word then (
      pos := !pos + len;
      v)
    else fail ("expected " ^ word)
  in
  let parse_string () =
    expect '"';
    let buf = Buffer.create 16 in
    let rec go () =
      if !pos >= n then fail "unterminated string"
      else
        match s.[!pos] with
        | '"' ->
            advance ();
            Buffer.contents buf
        | '\\' ->
            advance ();
            if !pos >= n then fail "unterminated escape";
            let c = s.[!pos] in
            advance ();
            (match c with
            | '"' -> Buffer.add_char buf '"'
            | '\\' -> Buffer.add_char buf '\\'
            | '/' -> Buffer.add_char buf '/'
            | 'n' -> Buffer.add_char buf '\n'
            | 'r' -> Buffer.add_char buf '\r'
            | 't' -> Buffer.add_char buf '\t'
            | 'b' -> Buffer.add_char buf '\b'
            | 'f' -> Buffer.add_char buf '\012'
            | 'u' ->
                if !pos + 4 > n then fail "truncated \\u escape";
                let hex = String.sub s !pos 4 in
                pos := !pos + 4;
                let code =
                  try int_of_string ("0x" ^ hex)
                  with _ -> fail "bad \\u escape"
                in
                (* Encoded back as UTF-8. Surrogate pairs are not handled: a
               contract call containing one is beyond what this needs to do,
               and guessing would be worse than refusing. *)
                if code >= 0xD800 && code <= 0xDFFF then fail "surrogate pair"
                else if code < 0x80 then Buffer.add_char buf (Char.chr code)
                else if code < 0x800 then (
                  Buffer.add_char buf (Char.chr (0xC0 lor (code lsr 6)));
                  Buffer.add_char buf (Char.chr (0x80 lor (code land 0x3F))))
                else (
                  Buffer.add_char buf (Char.chr (0xE0 lor (code lsr 12)));
                  Buffer.add_char buf
                    (Char.chr (0x80 lor ((code lsr 6) land 0x3F)));
                  Buffer.add_char buf (Char.chr (0x80 lor (code land 0x3F))))
            | _ -> fail "unknown escape");
            go ()
        | c ->
            Buffer.add_char buf c;
            advance ();
            go ()
    in
    go ()
  in
  let parse_number () =
    let start = !pos in
    if peek () = Some '-' then advance ();
    let digits () =
      let d = ref 0 in
      while !pos < n && s.[!pos] >= '0' && s.[!pos] <= '9' do
        advance ();
        incr d
      done;
      if !d = 0 then fail "expected a digit"
    in
    digits ();
    if peek () = Some '.' then (
      advance ();
      digits ());
    (match peek () with
    | Some ('e' | 'E') ->
        advance ();
        (match peek () with Some ('+' | '-') -> advance () | _ -> ());
        digits ()
    | _ -> ());
    String.sub s start (!pos - start)
  in
  let rec parse_value () =
    skip_ws ();
    match peek () with
    | None -> fail "unexpected end of input"
    | Some '{' ->
        advance ();
        skip_ws ();
        if peek () = Some '}' then (
          advance ();
          Object [])
        else
          let rec members acc =
            skip_ws ();
            let k = parse_string () in
            skip_ws ();
            expect ':';
            let v = parse_value () in
            skip_ws ();
            match peek () with
            | Some ',' ->
                advance ();
                members ((k, v) :: acc)
            | Some '}' ->
                advance ();
                Object (List.rev ((k, v) :: acc))
            | _ -> fail "expected , or }"
          in
          members []
    | Some '[' ->
        advance ();
        skip_ws ();
        if peek () = Some ']' then (
          advance ();
          Array [])
        else
          let rec items acc =
            let v = parse_value () in
            skip_ws ();
            match peek () with
            | Some ',' ->
                advance ();
                items (v :: acc)
            | Some ']' ->
                advance ();
                Array (List.rev (v :: acc))
            | _ -> fail "expected , or ]"
          in
          items []
    | Some '"' -> String (parse_string ())
    | Some 't' -> literal "true" (Bool true)
    | Some 'f' -> literal "false" (Bool false)
    | Some 'n' -> literal "null" Null
    | Some _ -> Number (parse_number ())
  in
  match
    let v = parse_value () in
    skip_ws ();
    if !pos <> n then fail "trailing data";
    v
  with
  | v -> Ok v
  | exception Bad msg -> Error ("json: " ^ msg)

(* Back out as canonical JSON, which is what makes this useful: the round trip
   is the normalisation. *)
let rec to_json = function
  | Null -> Json_out.Raw "null"
  | Bool true -> Json_out.Raw "true"
  | Bool false -> Json_out.Raw "false"
  | Number text -> Json_out.Raw text
  | String s -> Json_out.Str s
  | Array items -> Json_out.Arr (List.map to_json items)
  | Object fields ->
      Json_out.Obj (List.map (fun (k, v) -> (k, to_json v)) fields)
