module Address = Cosmos_types.Address
module Coin = Cosmos_types.Coin
module Pb_bank = Cosmos_proto.Cosmos_bank_v1beta1_tx.Cosmos.Bank.V1beta1

(* Input and Output live in bank.proto, not tx.proto, even though MsgMultiSend
   is the only thing that uses them. *)
module Pb_bank_types = Cosmos_proto.Cosmos_bank_v1beta1_bank.Cosmos.Bank.V1beta1

module Pb_ibc =
  Cosmos_proto.Ibc_applications_transfer_v1_tx.Ibc.Applications.Transfer.V1

module Pb_wasm = Cosmos_proto.Cosmwasm_wasm_v1_tx.Cosmwasm.Wasm.V1

module Pb_height =
  Cosmos_proto.Ibc_core_client_v1_client.Ibc.Core.Client.V1.Height

type send = {
  from_address : Address.t;
  to_address : Address.t;
  amount : Coin.t list;
}

type io = { address : Address.t; coins : Coin.t list }
type multi_send = { inputs : io list; outputs : io list }
type timeout_height = { revision_number : int64; revision_height : int64 }

type ibc_transfer = {
  source_port : string;
  source_channel : string;
  token : Coin.t;
  sender : Address.t;
  receiver : string;
  timeout_height : timeout_height;
  timeout_timestamp : int64;
  memo : string;
}

type wasm_execute = {
  sender : Address.t;
  contract : Address.t;
  msg : string;
  funds : Coin.t list;
}

type t =
  | Send of send
  | Multi_send of multi_send
  | Ibc_transfer of ibc_transfer
  | Wasm_execute of wasm_execute
  | Opaque of { type_url : string; value : string; why : string }

let url_send = "/cosmos.bank.v1beta1.MsgSend"
let url_multi_send = "/cosmos.bank.v1beta1.MsgMultiSend"
let url_ibc_transfer = "/ibc.applications.transfer.v1.MsgTransfer"
let url_wasm_execute = "/cosmwasm.wasm.v1.MsgExecuteContract"

let type_url = function
  | Send _ -> url_send
  | Multi_send _ -> url_multi_send
  | Ibc_transfer _ -> url_ibc_transfer
  | Wasm_execute _ -> url_wasm_execute
  | Opaque { type_url; _ } -> type_url

let is_approvable = function Opaque _ -> false | _ -> true

(* --- decoding ----------------------------------------------------------- *)

let ( let* ) = Result.bind

let decode_send ~base (m : Pb_bank.MsgSend.t) =
  let* from_address = Wire.address_of_bech32 ~base m.from_address in
  let* to_address = Wire.address_of_bech32 ~base m.to_address in
  let* amount = Wire.coins_of_pb m.amount in
  Ok (Send { from_address; to_address; amount })

let decode_io ~base (i : Pb_bank_types.Input.t) =
  let* address = Wire.address_of_bech32 ~base i.address in
  let* coins = Wire.coins_of_pb i.coins in
  Ok { address; coins }

let decode_output ~base (o : Pb_bank_types.Output.t) =
  let* address = Wire.address_of_bech32 ~base o.address in
  let* coins = Wire.coins_of_pb o.coins in
  Ok { address; coins }

let rec map_result f acc = function
  | [] -> Ok (List.rev acc)
  | x :: rest -> (
      match f x with Error _ as e -> e | Ok v -> map_result f (v :: acc) rest)

let map_result f l = map_result f [] l

let decode_multi_send ~base (m : Pb_bank.MsgMultiSend.t) =
  let* inputs = map_result (decode_io ~base) m.inputs in
  let* outputs = map_result (decode_output ~base) m.outputs in
  Ok (Multi_send { inputs; outputs })

let decode_ibc_transfer ~base (m : Pb_ibc.MsgTransfer.t) =
  let* sender = Wire.address_of_bech32 ~base m.sender in
  let* token =
    match m.token with
    | Some c -> Wire.coin_of_pb c
    | None -> Error "MsgTransfer: no token"
  in
  let timeout_height =
    match m.timeout_height with
    | Some (h : Pb_height.t) ->
        {
          revision_number = h.revision_number;
          revision_height = h.revision_height;
        }
    | None -> { revision_number = 0L; revision_height = 0L }
  in
  Ok
    (Ibc_transfer
       {
         source_port = m.source_port;
         source_channel = m.source_channel;
         token;
         sender;
         receiver = m.receiver;
         timeout_height;
         timeout_timestamp = m.timeout_timestamp;
         memo = m.memo;
       })

let decode_wasm_execute ~base (m : Pb_wasm.MsgExecuteContract.t) =
  let* sender = Wire.address_of_bech32 ~base m.sender in
  let* contract = Wire.address_of_bech32 ~base m.contract in
  let* funds = Wire.coins_of_pb m.funds in
  Ok (Wasm_execute { sender; contract; msg = Bytes.to_string m.msg; funds })

let of_any ~base ~type_url ~value =
  let opaque why = Opaque { type_url; value; why } in
  let attempt decoder pb_module =
    match Wire.decode pb_module value with
    | Error e -> opaque e
    | Ok m -> ( match decoder ~base m with Ok v -> v | Error e -> opaque e)
  in
  if type_url = url_send then attempt decode_send (module Pb_bank.MsgSend)
  else if type_url = url_multi_send then
    attempt decode_multi_send (module Pb_bank.MsgMultiSend)
  else if type_url = url_ibc_transfer then
    attempt decode_ibc_transfer (module Pb_ibc.MsgTransfer)
  else if type_url = url_wasm_execute then
    attempt decode_wasm_execute (module Pb_wasm.MsgExecuteContract)
  else opaque "unrecognised type_url"

(* --- encoding ----------------------------------------------------------- *)

let io_to_pb (i : io) : Pb_bank_types.Input.t =
  { address = Address.to_bech32 i.address; coins = Wire.coins_to_pb i.coins }

let output_to_pb (i : io) : Pb_bank_types.Output.t =
  { address = Address.to_bech32 i.address; coins = Wire.coins_to_pb i.coins }

let to_any = function
  | Send s ->
      Ok
        ( url_send,
          Wire.encode
            (module Pb_bank.MsgSend)
            {
              from_address = Address.to_bech32 s.from_address;
              to_address = Address.to_bech32 s.to_address;
              amount = Wire.coins_to_pb s.amount;
            } )
  | Multi_send m ->
      Ok
        ( url_multi_send,
          Wire.encode
            (module Pb_bank.MsgMultiSend)
            {
              inputs = List.map io_to_pb m.inputs;
              outputs = List.map output_to_pb m.outputs;
            } )
  | Ibc_transfer t ->
      Ok
        ( url_ibc_transfer,
          Wire.encode
            (module Pb_ibc.MsgTransfer)
            {
              source_port = t.source_port;
              source_channel = t.source_channel;
              token = Some (Wire.coin_to_pb t.token);
              sender = Address.to_bech32 t.sender;
              receiver = t.receiver;
              timeout_height =
                Some
                  {
                    revision_number = t.timeout_height.revision_number;
                    revision_height = t.timeout_height.revision_height;
                  };
              timeout_timestamp = t.timeout_timestamp;
              memo = t.memo;
              encoding = "";
            } )
  | Wasm_execute w ->
      Ok
        ( url_wasm_execute,
          Wire.encode
            (module Pb_wasm.MsgExecuteContract)
            {
              sender = Address.to_bech32 w.sender;
              contract = Address.to_bech32 w.contract;
              msg = Bytes.of_string w.msg;
              funds = Wire.coins_to_pb w.funds;
            } )
  | Opaque { type_url; value; _ } ->
      (* Re-emits exactly what it was built from. A message this library cannot
       read is one it must not reshape. *)
      Ok (type_url, value)
