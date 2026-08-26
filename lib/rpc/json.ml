type t = Yojson.Safe.t

let malformed fmt = Printf.ksprintf (fun s -> Error (Error.Malformed s)) fmt

let parse s =
  match Yojson.Safe.from_string s with
  | v -> Ok v
  | exception Yojson.Json_error m -> malformed "not JSON: %s" m
  | exception _ -> malformed "not JSON"

let opt_field name = function
  | `Assoc fields -> (
      match List.assoc_opt name fields with
      | Some `Null | None -> None
      | Some v -> Some v)
  | _ -> None

let field name j =
  match j with
  | `Assoc fields -> (
      match List.assoc_opt name fields with
      | Some v -> Ok v
      | None -> malformed "no %S field" name)
  | _ -> malformed "expected an object with a %S field" name

let string_field name j =
  match field name j with
  | Error _ as e -> e
  | Ok (`String s) -> Ok s
  | Ok _ -> malformed "%S is not a string" name

let int_field name j =
  match field name j with
  | Error _ as e -> e
  | Ok (`Int n) -> Ok n
  | Ok _ -> malformed "%S is not a number" name

let int64_field name j =
  match field name j with
  | Error _ as e -> e
  | Ok (`String s) -> (
      match Int64.of_string_opt s with
      | Some n -> Ok n
      | None -> malformed "%S is not a decimal integer: %S" name s)
  | Ok (`Int n) ->
      (* Not accepted silently. A node that sent a bare number here is not the
       node this library was written against, and quietly coercing would hide
       a pin that has moved. *)
      malformed "%S is the number %d, but this field is a quoted integer" name n
  | Ok _ -> malformed "%S is not a quoted integer" name

let bool_field name j =
  match field name j with
  | Error _ as e -> e
  | Ok (`Bool b) -> Ok b
  | Ok _ -> malformed "%S is not a boolean" name

let base64_field name j =
  match opt_field name j with
  | None -> Ok ""
  | Some (`String s) -> (
      match Base64.decode s with
      | Ok v -> Ok v
      | Error (`Msg m) -> malformed "%S is not base64: %s" name m)
  | Some _ -> malformed "%S is not a string" name
