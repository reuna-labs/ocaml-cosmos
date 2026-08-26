module Address = Cosmos_types.Address
module Coin = Cosmos_types.Coin
module Denom = Cosmos_types.Denom
module Rpc = Cosmos_rpc
module Pb = Ocaml_protoc_plugin
module Pb_auth = Cosmos_proto.Cosmos_auth_v1beta1_query.Cosmos.Auth.V1beta1
module Pb_account = Cosmos_proto.Cosmos_auth_v1beta1_auth.Cosmos.Auth.V1beta1
module Pb_bank = Cosmos_proto.Cosmos_bank_v1beta1_query.Cosmos.Bank.V1beta1
module Pb_coin = Cosmos_proto.Cosmos_base_v1beta1_coin.Cosmos.Base.V1beta1.Coin
module Pb_service = Cosmos_proto.Cosmos_tx_v1beta1_service.Cosmos.Tx.V1beta1
module Any = Cosmos_proto.Google_protobuf_any.Google.Protobuf.Any

type 'a t = {
  service : string;
  rpc : string;
  request : string;
  decode : string -> ('a, Rpc.Error.t) result;
}

module type MESSAGE = sig
  type t

  val to_proto : t -> Pb.Writer.t
  val from_proto : Pb.Reader.t -> (t, [> Pb.Result.error ]) result
end

let ( let* ) = Result.bind

let encode (type a) (module M : MESSAGE with type t = a) (v : a) =
  Pb.Writer.contents (M.to_proto v)

let decode_pb (type a) (module M : MESSAGE with type t = a) (bytes : string) =
  match M.from_proto (Pb.Reader.create bytes) with
  | Ok v -> Ok v
  | Error _ -> Error (Rpc.Error.Malformed "protobuf response would not decode")
  | exception _ ->
      Error (Rpc.Error.Malformed "protobuf response would not decode")

let url_base_account = "/cosmos.auth.v1beta1.BaseAccount"

(* The same decoders the JSON-RPC client uses, applied to the same protobuf.
   That is the point of having both transports: they differ in how the bytes
   travel and agree on what the bytes mean. *)
let account ~base addr =
  {
    service = "cosmos.auth.v1beta1.Query";
    rpc = "Account";
    request =
      encode (module Pb_auth.QueryAccountRequest) (Address.to_bech32 addr);
    decode =
      (fun bytes ->
        let* (resp : Pb_auth.QueryAccountResponse.t) =
          decode_pb (module Pb_auth.QueryAccountResponse) bytes
        in
        match resp with
        | None ->
            Error (Rpc.Error.Malformed "account response carried no account")
        | Some (any : Any.t) ->
            if any.type_url <> url_base_account then
              Ok (Rpc.Query.Other { type_url = any.type_url })
            else
              let* (acct : Pb_account.BaseAccount.t) =
                decode_pb
                  (module Pb_account.BaseAccount)
                  (Bytes.to_string any.value)
              in
              let* address =
                match Address.of_bech32 ~base acct.address with
                | Ok a -> Ok a
                | Error e -> Error (Rpc.Error.Malformed e)
              in
              Ok
                (Rpc.Query.Base
                   {
                     Rpc.Query.address;
                     account_number = acct.account_number;
                     sequence = acct.sequence;
                     has_public_key = acct.pub_key <> None;
                   }));
  }

let balance ~base:_ addr ~denom =
  {
    service = "cosmos.bank.v1beta1.Query";
    rpc = "Balance";
    request =
      encode
        (module Pb_bank.QueryBalanceRequest)
        { address = Address.to_bech32 addr; denom = Denom.to_string denom };
    decode =
      (fun bytes ->
        let* (resp : Pb_bank.QueryBalanceResponse.t) =
          decode_pb (module Pb_bank.QueryBalanceResponse) bytes
        in
        match resp with
        | None -> Error (Rpc.Error.Malformed "balance response carried no coin")
        | Some (c : Pb_coin.t) -> (
            match Coin.of_strings ~denom:c.denom ~amount:c.amount with
            | Ok coin -> Ok coin
            | Error e -> Error (Rpc.Error.Malformed e)));
  }

let[@alert "-protobuf"] simulate ~tx_bytes =
  {
    service = "cosmos.tx.v1beta1.Service";
    rpc = "Simulate";
    (* tx is deprecated in favour of tx_bytes; naming the field is what raises
       the alert, and nothing here ever sets it. *)
    request =
      encode
        (module Pb_service.SimulateRequest)
        { tx = None; tx_bytes = Bytes.of_string tx_bytes };
    decode =
      (fun bytes ->
        let* (resp : Pb_service.SimulateResponse.t) =
          decode_pb (module Pb_service.SimulateResponse) bytes
        in
        match resp.gas_info with
        | None -> Error (Rpc.Error.Malformed "simulation carried no gas info")
        | Some g ->
            Ok { Simulation.gas_wanted = g.gas_wanted; gas_used = g.gas_used });
  }
