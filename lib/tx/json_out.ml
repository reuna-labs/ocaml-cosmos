(* A canonical JSON writer.
   
   Not a JSON library. It writes, it does not read, and it offers exactly the
   shapes amino JSON needs. That is deliberate on two counts: it keeps yojson
   out of the offline closure, and a general library would let a caller emit
   something that is valid JSON and not canonical -- which for signed data is
   the same as emitting the wrong thing.
   
   Canonical here means what the SDK's encoder produces: object keys sorted by
   their UTF-8 bytes, no whitespace anywhere, and integers written as decimal
   strings rather than JSON numbers. *)

type t =
  | Str of string
  | Obj of (string * t) list
  | Arr of t list
  | Raw of string  (** Already-canonical JSON, spliced in verbatim. *)

let escape buf s =
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string buf "\\\""
      | '\\' -> Buffer.add_string buf "\\\\"
      | '\n' -> Buffer.add_string buf "\\n"
      | '\r' -> Buffer.add_string buf "\\r"
      | '\t' -> Buffer.add_string buf "\\t"
      | '\b' -> Buffer.add_string buf "\\b"
      | '\012' -> Buffer.add_string buf "\\f"
      | c when Char.code c < 0x20 ->
          Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char buf c)
    s

let rec write buf = function
  | Str s ->
      Buffer.add_char buf '"';
      escape buf s;
      Buffer.add_char buf '"'
  | Raw s -> Buffer.add_string buf s
  | Arr items ->
      Buffer.add_char buf '[';
      List.iteri
        (fun i v ->
          if i > 0 then Buffer.add_char buf ',';
          write buf v)
        items;
      Buffer.add_char buf ']'
  | Obj fields ->
      (* Sorted by key. The SDK sorts, so a writer that preserved insertion
       order would produce bytes a node will not verify. *)
      let fields = List.sort (fun (a, _) (b, _) -> String.compare a b) fields in
      Buffer.add_char buf '{';
      List.iteri
        (fun i (k, v) ->
          if i > 0 then Buffer.add_char buf ',';
          Buffer.add_char buf '"';
          escape buf k;
          Buffer.add_string buf "\":";
          write buf v)
        fields;
      Buffer.add_char buf '}'

let to_string v =
  let buf = Buffer.create 256 in
  write buf v;
  Buffer.contents buf
