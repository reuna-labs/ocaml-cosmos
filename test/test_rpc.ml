(* Decoding what a node actually sends.

   conformance/fixtures/rpc holds responses recorded from a public Cosmos Hub
   node by conformance/rpc/record.sh. They are not shaped from CometBFT's Go
   structs, and the difference matters: the structs do not show that int64
   fields are JSON strings while uint32 fields are JSON numbers, that absent
   fields are null rather than omitted, or that the key is "proofOps" in the
   middle of otherwise snake_case names.

   A decoder written from the type definitions passes review and fails against
   a node. *)

module Rpc = Cosmos_rpc
module Types = Cosmos_types
module Address = Types.Address

let ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "expected Ok, got %s" (Rpc.Error.to_string e)

let fixture name =
  let path = Filename.concat "../conformance/fixtures/rpc" (name ^ ".json") in
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let addr s =
  ok
    (Result.map_error
       (fun e -> Rpc.Error.Malformed e)
       (Address.of_bech32 ~base:"cosmos" s))

let key1 = "cosmos1w508d6qejxtdg4y5r3zarvary0c5xw7k6ah60c"

let status () =
  let s = ok (Rpc.Codec.response Rpc.Method.status (fixture "status")) in
  Alcotest.(check string)
    "chain id" "cosmoshub-4"
    (Types.Chain_id.to_string s.chain_id);
  Alcotest.(check bool)
    "a real height" true
    (s.latest_block_height > 30_000_000L);
  Alcotest.(check bool) "not catching up" false s.catching_up;
  Alcotest.(check bool) "a version" true (String.length s.node_version > 0)

let a_base_account () =
  (* The query a signer runs before it can build anything. The address is the
     BIP-173 example key, which exists on mainnet -- and whose public key on
     chain is the one conformance/oracle derives, so this doubles as a check
     that the address derivation lands where it should. *)
  let m = Rpc.Query.account ~base:"cosmos" (addr key1) in
  match ok (Rpc.Codec.response m (fixture "account_base")) with
  | Rpc.Query.Base a ->
      Alcotest.(check string)
        "the address comes back" key1
        (Address.to_bech32 a.address);
      Alcotest.(check bool) "an account number" true (a.account_number > 0L);
      Alcotest.(check bool) "a sequence" true (a.sequence >= 0L);
      Alcotest.(check bool) "and it has signed before" true a.has_public_key
  | Rpc.Query.Other { type_url } ->
      Alcotest.failf "expected a BaseAccount, got %s" type_url

let a_module_account () =
  (* The same query returning a different type inside the Any. A decoder that
     assumed BaseAccount would read this as nonsense rather than refusing it. *)
  let m = Rpc.Query.account ~base:"cosmos" (addr key1) in
  match ok (Rpc.Codec.response m (fixture "account_module")) with
  | Rpc.Query.Base _ ->
      Alcotest.fail "a module account decoded as a BaseAccount"
  | Rpc.Query.Other { type_url } ->
      Alcotest.(check string)
        "named, not decoded" "/cosmos.auth.v1beta1.ModuleAccount" type_url

let answered_no_is_not_did_not_answer () =
  let m = Rpc.Query.account ~base:"cosmos" (addr key1) in
  (* An account that does not exist: the node answered, and the answer is no.
     ABCI code 22 from the sdk codespace. *)
  (match Rpc.Codec.response m (fixture "account_missing") with
  | Ok _ -> Alcotest.fail "a missing account decoded as an account"
  | Error (Rpc.Error.Abci { code; codespace; log }) ->
      Alcotest.(check int) "code" 22 code;
      Alcotest.(check string) "codespace" "sdk" codespace;
      Alcotest.(check bool) "and the log says so" true (String.length log > 0)
  | Error e ->
      Alcotest.failf "expected an Abci error, got %s" (Rpc.Error.to_string e));
  (* A malformed address is a different code, and worth keeping distinct: "you
     asked wrong" is not "there is nothing there". *)
  (match Rpc.Codec.response m (fixture "account_bad_address") with
  | Error (Rpc.Error.Abci { code; _ }) ->
      Alcotest.(check int) "a different code" 18 code
  | _ -> Alcotest.fail "expected an Abci error");
  (* An envelope error: the node refused the request itself. *)
  match
    Rpc.Codec.response Rpc.Method.status (fixture "error_unknown_method")
  with
  | Error (Rpc.Error.Rpc { code; message }) ->
      Alcotest.(check int) "JSON-RPC method not found" (-32601) code;
      Alcotest.(check string) "message" "Method not found" message
  | _ -> Alcotest.fail "expected an Rpc error"

let retryable_means_transport_only () =
  (* The distinction is what stops a client hammering a query that will never
     succeed, and what stops it giving up on one that would. *)
  Alcotest.(check bool)
    "transport" true
    (Rpc.Error.is_retryable (Rpc.Error.Transport "connection reset"));
  Alcotest.(check bool)
    "abci" false
    (Rpc.Error.is_retryable
       (Rpc.Error.Abci { code = 22; codespace = "sdk"; log = "" }));
  Alcotest.(check bool)
    "rpc" false
    (Rpc.Error.is_retryable (Rpc.Error.Rpc { code = -32601; message = "" }));
  Alcotest.(check bool)
    "malformed" false
    (Rpc.Error.is_retryable (Rpc.Error.Malformed "nonsense"))

let quoted_integers_are_not_numbers () =
  (* The rule that a decoder written from the Go structs gets wrong. A node
     sends "height":"32675057" and "code":0 in the same object. *)
  let j = ok (Rpc.Json.parse {|{"height":"123","code":7}|}) in
  Alcotest.(check string)
    "a quoted integer reads" "123"
    (Int64.to_string (ok (Rpc.Json.int64_field "height" j)));
  Alcotest.(check int) "a bare one reads" 7 (ok (Rpc.Json.int_field "code" j));
  (* And neither accepts the other's form, so a pin that moved would be loud
     rather than silently coerced. *)
  (match Rpc.Json.int64_field "code" j with
  | Error (Rpc.Error.Malformed _) -> ()
  | _ -> Alcotest.fail "a bare number was accepted as a quoted integer");
  match Rpc.Json.int_field "height" j with
  | Error (Rpc.Error.Malformed _) -> ()
  | _ -> Alcotest.fail "a quoted integer was accepted as a number"

let null_is_absent () =
  (* CometBFT writes null rather than omitting, so the two have to mean the
     same thing. "value":null is what a failed query carries. *)
  let j = ok (Rpc.Json.parse {|{"value":null,"proofOps":null}|}) in
  Alcotest.(check string)
    "null base64 is empty" ""
    (ok (Rpc.Json.base64_field "value" j));
  Alcotest.(check string)
    "so is absent" ""
    (ok (Rpc.Json.base64_field "nothing" j));
  Alcotest.(check bool)
    "and opt_field agrees" true
    (Rpc.Json.opt_field "value" j = None)

let a_hostile_response_does_not_crash () =
  (* The node is the adversary. Every one of these is refused rather than
     raising, which is the property the whole decoder is written for. *)
  List.iter
    (fun body ->
      match Rpc.Codec.response Rpc.Method.status body with
      | Ok _ -> Alcotest.failf "accepted %S" body
      | Error _ -> ())
    [
      "";
      "not json";
      "{";
      "[]";
      "null";
      {|{"jsonrpc":"2.0"}|};
      {|{"jsonrpc":"2.0","result":null}|};
      {|{"jsonrpc":"2.0","result":{}}|};
      {|{"jsonrpc":"2.0","result":{"node_info":{},"sync_info":{}}}|};
      {|{"jsonrpc":"2.0","result":{"node_info":{"network":"","version":"x"},"sync_info":{"latest_block_height":"1","latest_block_time":"t","catching_up":false}}}|};
      {|{"jsonrpc":"2.0","error":{}}|};
      {|{"jsonrpc":"2.0","result":{"node_info":{"network":1}}}|};
    ]

let requests_are_well_formed () =
  let r = Rpc.Codec.request ~id:1 Rpc.Method.status in
  Alcotest.(check string)
    "status" {|{"jsonrpc":"2.0","id":1,"method":"status","params":{}}|} r;
  (* An ABCI query sends its data as 0x-prefixed hex ... *)
  let q = Rpc.Method.abci_query ~path:"/x.Y/Z" ~data:"\x01\xff" in
  Alcotest.(check string)
    "abci_query"
    {|{"jsonrpc":"2.0","id":2,"method":"abci_query","params":{"path":"/x.Y/Z","data":"0x01ff"}}|}
    (Rpc.Codec.request ~id:2 q);
  (* ... and a broadcast sends its transaction as base64. The two are not
     interchangeable and a node accepts neither in the other's place. *)
  let b = Rpc.Method.broadcast_tx_sync "\x01\xff" in
  Alcotest.(check string)
    "broadcast_tx_sync"
    {|{"jsonrpc":"2.0","id":3,"method":"broadcast_tx_sync","params":{"tx":"Af8="}}|}
    (Rpc.Codec.request ~id:3 b)

let () =
  Alcotest.run "cosmos-rpc"
    [
      ( "recorded from a node",
        [
          Alcotest.test_case "status" `Quick status;
          Alcotest.test_case "a base account" `Quick a_base_account;
          Alcotest.test_case "a module account" `Quick a_module_account;
          Alcotest.test_case "answered no is not did not answer" `Quick
            answered_no_is_not_did_not_answer;
        ] );
      ( "the shapes that catch people out",
        [
          Alcotest.test_case "quoted integers are not numbers" `Quick
            quoted_integers_are_not_numbers;
          Alcotest.test_case "null is absent" `Quick null_is_absent;
        ] );
      ( "defensive",
        [
          Alcotest.test_case "a hostile response does not crash" `Quick
            a_hostile_response_does_not_crash;
          Alcotest.test_case "retryable means transport only" `Quick
            retryable_means_transport_only;
        ] );
      ( "requests",
        [ Alcotest.test_case "well formed" `Quick requests_are_well_formed ] );
    ]
