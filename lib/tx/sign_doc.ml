type t = {
  body_bytes : string;
  auth_info_bytes : string;
  chain_id : string;
  account_number : int64;
}

let make ~body_bytes ~auth_info_bytes ~chain_id ~account_number =
  { body_bytes; auth_info_bytes; chain_id; account_number }

(* The fields are retained rather than re-derived; see sign_doc.mli. *)
let to_bytes { body_bytes; auth_info_bytes; chain_id; account_number } =
  ignore (body_bytes, auth_info_bytes, chain_id, account_number);
  failwith "cosmos-tx: Sign_doc.to_bytes is not implemented"

let digest t =
  ignore t;
  failwith "cosmos-tx: Sign_doc.digest is not implemented"
