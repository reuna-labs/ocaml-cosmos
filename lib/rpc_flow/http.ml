type limits = { max_header_bytes : int; max_body_bytes : int }

let default_limits =
  { max_header_bytes = 65_536; max_body_bytes = 8 * 1024 * 1024 }

let request ~host ~path body =
  Printf.sprintf
    "POST %s HTTP/1.1\r\n\
     Host: %s\r\n\
     Content-Type: application/json\r\n\
     Accept: application/json\r\n\
     Content-Length: %d\r\n\
     \r\n\
     %s"
    path host (String.length body) body

type response = { status : int; body : string }

type body_kind =
  | Fixed of int
  | Chunked
  | Until_close
      (** No length and no chunking. Legal in HTTP/1.1 only when the connection
          closes to mark the end, which CometBFT does not do -- but a response
          that omits both has to be handled rather than assumed impossible. *)

type phase =
  | Headers
  | Body of { kind : body_kind; got : Buffer.t }
  | Chunk_size of { got : Buffer.t }
  | Chunk_data of { remaining : int; got : Buffer.t }
  | Complete of response

type state = { limits : limits; buf : Buffer.t; status : int; phase : phase }

let start limits =
  { limits; buf = Buffer.create 1024; status = 0; phase = Headers }

let result t = match t.phase with Complete r -> Some r | _ -> None

let find_sub hay needle from =
  let n = String.length needle and m = String.length hay in
  let rec go i =
    if i + n > m then None
    else if String.sub hay i n = needle then Some i
    else go (i + 1)
  in
  go from

let lowercase = String.lowercase_ascii

(* Parses the status line and headers. Returns the body kind and the offset the
   body starts at. *)
let parse_headers block =
  match String.index_opt block '\r' with
  | None -> Error "no status line"
  | Some eol ->
      let status_line = String.sub block 0 eol in
      let status =
        match String.split_on_char ' ' status_line with
        | _ :: code :: _ -> (
            match int_of_string_opt code with Some c -> c | None -> 0)
        | _ -> 0
      in
      if status = 0 then Error ("unparseable status line: " ^ status_line)
      else begin
        let lines =
          String.split_on_char '\n'
            (String.sub block (eol + 2) (String.length block - eol - 2))
        in
        let kind = ref Until_close in
        let bad = ref None in
        List.iter
          (fun line ->
            let line = String.trim line in
            if line <> "" then
              match String.index_opt line ':' with
              | None -> ()
              | Some i ->
                  let name = lowercase (String.trim (String.sub line 0 i)) in
                  let value =
                    String.trim
                      (String.sub line (i + 1) (String.length line - i - 1))
                  in
                  if name = "content-length" then
                    match int_of_string_opt value with
                    | Some n when n >= 0 -> kind := Fixed n
                    | _ -> bad := Some ("bad Content-Length: " ^ value)
                  else if
                    name = "transfer-encoding" && lowercase value = "chunked"
                  then kind := Chunked)
          lines;
        match !bad with Some e -> Error e | None -> Ok (status, !kind)
      end

let too_big what limit = Error (Printf.sprintf "%s exceeds %d bytes" what limit)

let rec advance t =
  match t.phase with
  | Complete _ -> Ok t
  | Headers -> (
      let s = Buffer.contents t.buf in
      match find_sub s "\r\n\r\n" 0 with
      | None ->
          if String.length s > t.limits.max_header_bytes then
            too_big "header block" t.limits.max_header_bytes
          else Ok t
      | Some i -> (
          match parse_headers (String.sub s 0 i) with
          | Error _ as e -> e
          | Ok (status, kind) -> (
              let rest = String.sub s (i + 4) (String.length s - i - 4) in
              match kind with
              | Fixed n when n > t.limits.max_body_bytes ->
                  too_big "declared body" t.limits.max_body_bytes
              | Chunked ->
                  let t =
                    {
                      t with
                      status;
                      phase = Chunk_size { got = Buffer.create 1024 };
                    }
                  in
                  Buffer.clear t.buf;
                  Buffer.add_string t.buf rest;
                  advance t
              | kind ->
                  let got = Buffer.create 1024 in
                  Buffer.add_string got rest;
                  let t = { t with status; phase = Body { kind; got } } in
                  Buffer.clear t.buf;
                  advance t)))
  | Body { kind; got } -> (
      if Buffer.length got > t.limits.max_body_bytes then
        too_big "body" t.limits.max_body_bytes
      else
        match kind with
        | Fixed n when Buffer.length got >= n ->
            Ok
              {
                t with
                phase =
                  Complete { status = t.status; body = Buffer.sub got 0 n };
              }
        | _ -> Ok t)
  | Chunk_size { got } -> (
      let s = Buffer.contents t.buf in
      match find_sub s "\r\n" 0 with
      | None ->
          if String.length s > 64 then Error "chunk size line is too long"
          else Ok t
      | Some i -> (
          let line = String.sub s 0 i in
          (* A chunk-size line may carry extensions after a semicolon. *)
          let hex =
            match String.index_opt line ';' with
            | Some j -> String.sub line 0 j
            | None -> line
          in
          let hex = String.trim hex in
          match int_of_string_opt ("0x" ^ hex) with
          | None -> Error ("bad chunk size: " ^ hex)
          | Some 0 ->
              (* The trailer is not parsed; a JSON-RPC response has nothing in it
           this client would act on. *)
              Ok
                {
                  t with
                  phase =
                    Complete { status = t.status; body = Buffer.contents got };
                }
          | Some n ->
              if Buffer.length got + n > t.limits.max_body_bytes then
                too_big "chunked body" t.limits.max_body_bytes
              else begin
                let rest = String.sub s (i + 2) (String.length s - i - 2) in
                Buffer.clear t.buf;
                Buffer.add_string t.buf rest;
                advance { t with phase = Chunk_data { remaining = n; got } }
              end))
  | Chunk_data { remaining; got } ->
      let available = Buffer.length t.buf in
      if available < remaining + 2 then Ok t
      else begin
        let s = Buffer.contents t.buf in
        Buffer.add_string got (String.sub s 0 remaining);
        let rest =
          String.sub s (remaining + 2) (String.length s - remaining - 2)
        in
        Buffer.clear t.buf;
        Buffer.add_string t.buf rest;
        advance { t with phase = Chunk_size { got } }
      end

let feed t chunk =
  match t.phase with
  | Complete _ -> Ok t
  | Body { got; kind } ->
      if Buffer.length got + String.length chunk > t.limits.max_body_bytes then
        too_big "body" t.limits.max_body_bytes
      else begin
        Buffer.add_string got chunk;
        advance { t with phase = Body { got; kind } }
      end
  | _ ->
      Buffer.add_string t.buf chunk;
      advance t
