module Address = Cosmos_types.Address
module Coin = Cosmos_types.Coin
module Pb = Cosmos_proto.Cosmos_tx_v1beta1_tx.Cosmos.Tx.V1beta1
module Any = Cosmos_proto.Google_protobuf_any.Google.Protobuf.Any

module Pb_signing =
  Cosmos_proto.Cosmos_tx_signing_v1beta1_signing.Cosmos.Tx.Signing.V1beta1

module Pb_secp =
  Cosmos_proto.Cosmos_crypto_secp256k1_keys.Cosmos.Crypto.Secp256k1

type sign_mode = Direct | Legacy_amino_json | Other of int

type public_key =
  | Secp256k1 of Cosmos_crypto.public_key
  | Other_key of { type_url : string; value : string }

type signer = {
  public_key : public_key option;
  mode : sign_mode;
  sequence : int64;
}

type fee = {
  amount : Coin.t list;
  gas_limit : int64;
  payer : Address.t option;
  granter : Address.t option;
}

type t = { signers : signer list; fee : fee; source : string }

let signers t = t.signers
let fee t = t.fee
let to_bytes t = t.source
let has_fee_delegation t = t.fee.payer <> None || t.fee.granter <> None
let url_secp256k1 = "/cosmos.crypto.secp256k1.PubKey"
let ( let* ) = Result.bind

(* --- sign modes --------------------------------------------------------- *)

let mode_of_pb : Pb_signing.SignMode.t -> sign_mode = function
  | SIGN_MODE_DIRECT -> Direct
  | SIGN_MODE_LEGACY_AMINO_JSON -> Legacy_amino_json
  | SIGN_MODE_UNSPECIFIED -> Other 0
  | SIGN_MODE_DIRECT_AUX -> Other 3
  | SIGN_MODE_EIP_191 -> Other 191

let mode_to_pb : sign_mode -> Pb_signing.SignMode.t = function
  | Direct -> SIGN_MODE_DIRECT
  | Legacy_amino_json -> SIGN_MODE_LEGACY_AMINO_JSON
  | Other 3 -> SIGN_MODE_DIRECT_AUX
  | Other 191 -> SIGN_MODE_EIP_191
  | Other _ -> SIGN_MODE_UNSPECIFIED

(* --- public keys -------------------------------------------------------- *)

let key_of_any (a : Any.t) =
  let value = Bytes.to_string a.value in
  if a.type_url = url_secp256k1 then
    (* PubKey has one field, so the generated type is the field itself rather
       than a record wrapping it. *)
    match Wire.decode (module Pb_secp.PubKey) value with
    | Error _ -> Other_key { type_url = a.type_url; value }
    | Ok (key : Pb_secp.PubKey.t) -> (
        match Cosmos_crypto.public_key_of_bytes (Bytes.to_string key) with
        | Ok k -> Secp256k1 k
        | Error _ -> Other_key { type_url = a.type_url; value })
  else Other_key { type_url = a.type_url; value }

let key_to_any = function
  | Secp256k1 k ->
      ({
         type_url = url_secp256k1;
         value =
           Bytes.of_string
             (Wire.encode
                (module Pb_secp.PubKey)
                (Bytes.of_string (Cosmos_crypto.compressed k)));
       }
        : Any.t)
  | Other_key { type_url; value } -> { type_url; value = Bytes.of_string value }

(* --- construction ------------------------------------------------------- *)

let signer_to_pb (s : signer) : Pb.SignerInfo.t =
  {
    public_key = Option.map key_to_any s.public_key;
    (* Single has one field too, so it unwraps to the SignMode itself. *)
    mode_info = Some (`Single (mode_to_pb s.mode));
    sequence = s.sequence;
  }

let fee_to_pb (f : fee) : Pb.Fee.t =
  {
    amount = Wire.coins_to_pb f.amount;
    gas_limit = f.gas_limit;
    payer = (match f.payer with Some a -> Address.to_bech32 a | None -> "");
    granter =
      (match f.granter with Some a -> Address.to_bech32 a | None -> "");
  }

let[@alert "-protobuf"] make ~signers ~fee =
  if signers = [] then Error "auth_info: no signers"
  else if fee.gas_limit <= 0L then Error "auth_info: gas limit must be positive"
  else
    let pb : Pb.AuthInfo.t =
      {
        signer_infos = List.map signer_to_pb signers;
        fee = Some (fee_to_pb fee);
        (* Tips were withdrawn: the field is deprecated upstream and nothing
           here ever sets one. It has to be mentioned because the record is
           exhaustive, and naming it is what raises the alert -- silenced for
           this expression only, so a deprecation anywhere else still shows. *)
        tip = None;
      }
    in
    Ok { signers; fee; source = Wire.encode (module Pb.AuthInfo) pb }

let address_opt ~base = function
  | "" -> Ok None
  | s -> (
      match Address.of_bech32 ~base s with
      | Ok a -> Ok (Some a)
      | Error e -> Error e)

let signer_of_pb (s : Pb.SignerInfo.t) =
  let mode =
    match s.mode_info with
    | Some (`Single m) -> mode_of_pb m
    | Some (`Multi _) ->
        (* A multisig signer's mode is a list, not one value. Reporting the outer
         mode as anything specific would be a claim this library has not
         checked; Other 0 says "not a mode I can name". *)
        Other 0
    | Some `not_set | None -> Other 0
  in
  Ok
    {
      public_key = Option.map key_of_any s.public_key;
      mode;
      sequence = s.sequence;
    }

let rec map_result f acc = function
  | [] -> Ok (List.rev acc)
  | x :: rest -> (
      match f x with Error _ as e -> e | Ok v -> map_result f (v :: acc) rest)

let map_result f l = map_result f [] l

let of_bytes ~base source =
  let* (pb : Pb.AuthInfo.t) = Wire.decode (module Pb.AuthInfo) source in
  let* signers = map_result signer_of_pb pb.signer_infos in
  let* fee =
    match pb.fee with
    | None -> Error "auth_info: no fee"
    | Some f ->
        let* amount = Wire.coins_of_pb f.amount in
        let* payer = address_opt ~base f.payer in
        let* granter = address_opt ~base f.granter in
        Ok { amount; gas_limit = f.gas_limit; payer; granter }
  in
  Ok { signers; fee; source }
