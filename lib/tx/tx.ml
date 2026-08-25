module Pb = Cosmos_proto.Cosmos_tx_v1beta1_tx.Cosmos.Tx.V1beta1
module Chain_id = Cosmos_types.Chain_id

type t = {
  body : Body.t;
  auth_info : Auth_info.t;
  signatures : string list;
  source : string;
}

let body t = t.body
let auth_info t = t.auth_info
let signatures t = t.signatures
let to_bytes t = t.source
let hash t = Digestif.SHA256.(to_raw_string (digest_string t.source))
let ( let* ) = Result.bind

(* TxRaw's own fields are bytes, so building it from the kept body and
   auth-info bytes is not a re-encode of anything: those two strings pass
   through untouched. It is the only place in this library where the generated
   writer is handed something that was decoded elsewhere, and it is safe for
   exactly that reason. *)
let frame ~body_bytes ~auth_info_bytes ~signatures =
  Wire.encode
    (module Pb.TxRaw)
    {
      body_bytes = Bytes.of_string body_bytes;
      auth_info_bytes = Bytes.of_string auth_info_bytes;
      signatures = List.map Bytes.of_string signatures;
    }

let sign ~body ~auth_info ~chain_id ~account_number ~key =
  let doc = Sign_doc.make ~body ~auth_info ~chain_id ~account_number in
  let* signature = Cosmos_crypto.sign_digest ~key (Sign_doc.digest doc) in
  let signatures = [ Cosmos_crypto.signature_to_bytes signature ] in
  Ok
    {
      body;
      auth_info;
      signatures;
      source =
        frame ~body_bytes:(Sign_doc.body_bytes doc)
          ~auth_info_bytes:(Sign_doc.auth_info_bytes doc)
          ~signatures;
    }

let of_bytes ~base source =
  let* (raw : Pb.TxRaw.t) = Wire.decode (module Pb.TxRaw) source in
  let* body = Body.of_bytes ~base (Bytes.to_string raw.body_bytes) in
  let* auth_info =
    Auth_info.of_bytes ~base (Bytes.to_string raw.auth_info_bytes)
  in
  Ok
    {
      body;
      auth_info;
      signatures = List.map Bytes.to_string raw.signatures;
      source;
    }

let verify t ~chain_id ~account_number =
  let doc =
    Sign_doc.make ~body:t.body ~auth_info:t.auth_info ~chain_id ~account_number
  in
  let digest = Sign_doc.digest doc in
  let signers = Auth_info.signers t.auth_info in
  List.length signers = List.length t.signatures
  && List.for_all2
       (fun (s : Auth_info.signer) sg ->
         match (s.public_key, Cosmos_crypto.signature_of_bytes sg) with
         | Some (Auth_info.Secp256k1 key), Ok sg ->
             Cosmos_crypto.verify_digest ~key sg digest
         | _ -> false)
       signers t.signatures
