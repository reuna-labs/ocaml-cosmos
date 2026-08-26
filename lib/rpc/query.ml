module Address = Cosmos_types.Address
module Coin = Cosmos_types.Coin
module Denom = Cosmos_types.Denom
module Pb_auth = Cosmos_proto.Cosmos_auth_v1beta1_query.Cosmos.Auth.V1beta1
module Pb_account = Cosmos_proto.Cosmos_auth_v1beta1_auth.Cosmos.Auth.V1beta1
module Pb_bank = Cosmos_proto.Cosmos_bank_v1beta1_query.Cosmos.Bank.V1beta1
module Pb_coin = Cosmos_proto.Cosmos_base_v1beta1_coin.Cosmos.Base.V1beta1.Coin
module Any = Cosmos_proto.Google_protobuf_any.Google.Protobuf.Any
module Pb = Ocaml_protoc_plugin

type account = {
  address : Address.t;
  account_number : int64;
  sequence : int64;
  has_public_key : bool;
}

type account_result = Base of account | Other of { type_url : string }

let ( let* ) = Result.bind

(* The same seam cosmos-tx has in Wire, restated here because it is five lines
   and because the two want different things from it: that one also converts
   coins and addresses, and this one turns failures into Error.t rather than
   into strings. *)
module type MESSAGE = sig
  type t

  val to_proto : t -> Pb.Writer.t
  val from_proto : Pb.Reader.t -> (t, [> Pb.Result.error ]) result
end

let encode (type a) (module M : MESSAGE with type t = a) (v : a) =
  Pb.Writer.contents (M.to_proto v)

let decode_pb (type a) (module M : MESSAGE with type t = a) (bytes : string) =
  (* The reader can raise as well as return an error; both are caught, because
     these bytes came from a node. *)
  match M.from_proto (Pb.Reader.create bytes) with
  | Ok v -> Ok v
  | Error _ -> Error (Error.Malformed "protobuf response would not decode")
  | exception _ -> Error (Error.Malformed "protobuf response would not decode")

let url_base_account = "/cosmos.auth.v1beta1.BaseAccount"

let account ~base addr =
  let request =
    (* One field, so the generated type is the field itself. *)
    encode (module Pb_auth.QueryAccountRequest) (Address.to_bech32 addr)
  in
  Method.map
    (fun (r : Method.abci_response) ->
      let* (resp : Pb_auth.QueryAccountResponse.t) =
        decode_pb (module Pb_auth.QueryAccountResponse) r.value
      in
      match resp with
      | None -> Error (Error.Malformed "account response carried no account")
      | Some (any : Any.t) ->
          if any.type_url <> url_base_account then
            Ok (Other { type_url = any.type_url })
          else
            let* (acct : Pb_account.BaseAccount.t) =
              decode_pb
                (module Pb_account.BaseAccount)
                (Bytes.to_string any.value)
            in
            let* address =
              match Address.of_bech32 ~base acct.address with
              | Ok a -> Ok a
              | Error e -> Error (Error.Malformed e)
            in
            Ok
              (Base
                 {
                   address;
                   account_number = acct.account_number;
                   sequence = acct.sequence;
                   has_public_key = acct.pub_key <> None;
                 }))
    (Method.abci_query ~path:"/cosmos.auth.v1beta1.Query/Account" ~data:request)

let balance ~base:_ addr ~denom =
  let request =
    encode
      (module Pb_bank.QueryBalanceRequest)
      { address = Address.to_bech32 addr; denom = Denom.to_string denom }
  in
  Method.map
    (fun (r : Method.abci_response) ->
      let* (resp : Pb_bank.QueryBalanceResponse.t) =
        decode_pb (module Pb_bank.QueryBalanceResponse) r.value
      in
      match resp with
      | None -> Error (Error.Malformed "balance response carried no coin")
      | Some (c : Pb_coin.t) -> (
          match Coin.of_strings ~denom:c.denom ~amount:c.amount with
          | Ok coin -> Ok coin
          | Error e -> Error (Error.Malformed e)))
    (Method.abci_query ~path:"/cosmos.bank.v1beta1.Query/Balance" ~data:request)
