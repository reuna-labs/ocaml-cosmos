type t = Buffer.t

let create domain =
  let b = Buffer.create 256 in
  (* The domain goes in length-prefixed too, so a longer domain cannot be
     confused with a shorter one followed by a field. *)
  Buffer.add_int32_be b (Int32.of_int (String.length domain));
  Buffer.add_string b domain;
  b

let string t s =
  Buffer.add_int32_be t (Int32.of_int (String.length s));
  Buffer.add_string t s;
  t

let int64 t n =
  Buffer.add_int64_be t n;
  t

let byte t n =
  Buffer.add_uint8 t (n land 0xff);
  t

let contents t = Buffer.contents t
let digest t = Digestif.SHA256.(to_raw_string (digest_string (contents t)))
