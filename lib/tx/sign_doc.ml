module Pb = Cosmos_proto.Cosmos_tx_v1beta1_tx.Cosmos.Tx.V1beta1
module Chain_id = Cosmos_types.Chain_id

type t = {
  body_bytes : string;
  auth_info_bytes : string;
  chain_id : Chain_id.t;
  account_number : int64;
}

let make ~body ~auth_info ~chain_id ~account_number =
  {
    (* The kept bytes, not a re-encode. See the .mli. *)
    body_bytes = Body.to_bytes body;
    auth_info_bytes = Auth_info.to_bytes auth_info;
    chain_id;
    account_number;
  }

let of_bytes source =
  match Wire.decode (module Pb.SignDoc) source with
  | Error _ as e -> e
  | Ok (pb : Pb.SignDoc.t) -> (
      match Chain_id.of_string pb.chain_id with
      | Error e -> Error ("sign_doc: " ^ e)
      | Ok chain_id ->
          Ok
            {
              body_bytes = Bytes.to_string pb.body_bytes;
              auth_info_bytes = Bytes.to_string pb.auth_info_bytes;
              chain_id;
              account_number = pb.account_number;
            })

let body_bytes t = t.body_bytes
let auth_info_bytes t = t.auth_info_bytes
let chain_id t = t.chain_id
let account_number t = t.account_number

let to_bytes t =
  Wire.encode
    (module Pb.SignDoc)
    {
      body_bytes = Bytes.of_string t.body_bytes;
      auth_info_bytes = Bytes.of_string t.auth_info_bytes;
      chain_id = Chain_id.to_string t.chain_id;
      account_number = t.account_number;
    }

let digest t = Digestif.SHA256.(to_raw_string (digest_string (to_bytes t)))
