module Rpc = Cosmos_rpc

let total f input = Crowbar.check (match f input with _ -> true)

let () =
  Crowbar.add_test ~name:"JSON parser never raises" [ Crowbar.bytes ]
    (fun input -> total Rpc.Json.parse input)

let () =
  Crowbar.add_test ~name:"status response never raises" [ Crowbar.bytes ]
    (fun input -> total (Rpc.Codec.response Rpc.Method.status) input)

let () =
  Crowbar.add_test ~name:"ABCI response never raises" [ Crowbar.bytes ]
    (fun input ->
      total
        (Rpc.Codec.response (Rpc.Method.abci_query ~path:"/x" ~data:""))
        input)

let () =
  Crowbar.add_test ~name:"broadcast response never raises" [ Crowbar.bytes ]
    (fun input ->
      total (Rpc.Codec.response (Rpc.Method.broadcast_tx_sync "tx")) input)

let () =
  Crowbar.add_test ~name:"transaction response never raises" [ Crowbar.bytes ]
    (fun input ->
      total
        (Rpc.Codec.response (Rpc.Method.tx ~hash:(String.make 32 '\x00')))
        input)

let () =
  Crowbar.add_test ~name:"JSON field accessors never raise" [ Crowbar.bytes ]
    (fun input ->
      match Rpc.Json.parse input with
      | Error _ -> ()
      | Ok json ->
          total (Rpc.Json.field "x") json;
          total (Rpc.Json.string_field "x") json;
          total (Rpc.Json.int_field "x") json;
          total (Rpc.Json.int64_field "x") json;
          total (Rpc.Json.bool_field "x") json;
          total (Rpc.Json.base64_field "x") json)
