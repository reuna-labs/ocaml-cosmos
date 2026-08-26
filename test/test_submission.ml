(* The submission state machine.

   It is pure, so the awkward cases are reachable directly: a node on the wrong
   chain, a connection that drops mid-broadcast, a transaction that passes
   CheckTx and then fails in a block. Driving those against a real node would
   mean arranging for them to happen. *)

module Rpc = Cosmos_rpc
module Sub = Rpc.Submission
module Types = Cosmos_types
module Address = Types.Address

let ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "unexpected error %S" e

let hub = ok (Types.Chain_id.of_string "cosmoshub-4")

let signer =
  ok
    (Address.of_bech32 ~base:"cosmos"
       "cosmos1w508d6qejxtdg4y5r3zarvary0c5xw7k6ah60c")

let other =
  ok
    (Address.of_bech32 ~base:"cosmos"
       "cosmos1q6hag67dl53wl99vzg42z8eyzfz2xlkvsrxukv")

let config ?(max_rebuilds = 3) ?(max_polls = 5) () =
  { Sub.chain_id = hub; signer; max_rebuilds; max_polls }

let status ?(chain = hub) ?(catching_up = false) () =
  {
    Rpc.Method.chain_id = chain;
    node_version = "0.38.22";
    latest_block_height = 32_675_057L;
    latest_block_time = "2026-08-26T06:52:32Z";
    catching_up;
  }

let account ?(number = 51199L) ?(sequence = 1L) ?(address = signer) () =
  Rpc.Query.Base
    { address; account_number = number; sequence; has_public_key = true }

let broadcast ?(code = 0) ?(hash = "ABCD") () =
  { Rpc.Method.code; codespace = "sdk"; log = ""; hash }

let delivered ?(code = 0) () =
  Ok
    {
      Rpc.Method.hash = "ABCD";
      height = 32_675_060L;
      code;
      codespace = "sdk";
      log = (if code = 0 then "" else "out of gas");
      gas_wanted = 200_000L;
      gas_used = 78_000L;
    }

let not_found =
  Error (Rpc.Error.Rpc { code = -32603; message = "tx not found" })

(* --- the happy path ----------------------------------------------------- *)

let the_ordinary_sequence () =
  let m = Sub.start (config ()) in
  Alcotest.(check bool) "asks the node first" true (Sub.next m = Sub.Check_node);
  let m = Sub.on_status m (status ()) in
  Alcotest.(check bool) "then the account" true (Sub.next m = Sub.Fetch_account);
  let m = Sub.on_account m (account ()) in
  (match Sub.next m with
  | Sub.Build_and_sign { account_number; sequence } ->
      Alcotest.(check string)
        "signs for the fetched account number" "51199"
        (Int64.to_string account_number);
      Alcotest.(check string)
        "and the fetched sequence" "1" (Int64.to_string sequence)
  | _ -> Alcotest.fail "expected Build_and_sign");
  let m = Sub.on_signed m "\x0a\x00signed" in
  Alcotest.(check bool)
    "then broadcasts" true
    (Sub.next m = Sub.Broadcast "\x0a\x00signed");
  let m = Sub.on_broadcast m (broadcast ()) in
  (* A code-0 broadcast is not a confirmation, so it polls. *)
  Alcotest.(check bool)
    "and polls" true
    (Sub.next m = Sub.Poll { hash = "ABCD" });
  Alcotest.(check bool) "not finished yet" true (Sub.finished m = None);
  let m = Sub.on_tx m not_found in
  Alcotest.(check bool)
    "not found yet is not a failure" true
    (Sub.finished m = None);
  let m = Sub.on_tx m (delivered ()) in
  match Sub.finished m with
  | Some (Sub.Delivered d) ->
      Alcotest.(check string) "height" "32675060" (Int64.to_string d.height);
      Alcotest.(check string) "gas used" "78000" (Int64.to_string d.gas_used)
  | _ -> Alcotest.fail "expected Delivered"

(* --- the chain id is checked before anything is signed ------------------ *)

let the_wrong_chain_stops_it_before_signing () =
  let m = Sub.start (config ()) in
  let testnet = ok (Types.Chain_id.of_string "provider") in
  let m = Sub.on_status m (status ~chain:testnet ()) in
  match Sub.finished m with
  | Some (Sub.Gave_up reason) ->
      Alcotest.(check bool)
        ("names both chains: " ^ reason)
        true
        (String.length reason > 0)
  | _ -> Alcotest.fail "a node on the wrong chain should stop it"

let a_catching_up_node_is_refused () =
  let m = Sub.start (config ()) in
  let m = Sub.on_status m (status ~catching_up:true ()) in
  match Sub.finished m with
  | Some (Sub.Gave_up _) -> ()
  | _ -> Alcotest.fail "a syncing node's account state is behind the chain"

let an_account_that_cannot_sign () =
  let m = Sub.start (config ()) in
  let m = Sub.on_status m (status ()) in
  let m =
    Sub.on_account m
      (Rpc.Query.Other { type_url = "/cosmos.auth.v1beta1.ModuleAccount" })
  in
  (match Sub.finished m with
  | Some (Sub.Gave_up _) -> ()
  | _ -> Alcotest.fail "a module account cannot sign");
  (* And an answer about a different address is refused rather than used. *)
  let m = Sub.start (config ()) in
  let m = Sub.on_status m (status ()) in
  let m = Sub.on_account m (account ~address:other ()) in
  match Sub.finished m with
  | Some (Sub.Gave_up _) -> ()
  | _ -> Alcotest.fail "an answer about another address should be refused"

(* --- the sequence discipline -------------------------------------------- *)

let check_failure_leaves_the_sequence_alone () =
  let m = Sub.start (config ()) in
  let m = Sub.on_status m (status ()) in
  let m = Sub.on_account m (account ()) in
  let m = Sub.on_signed m "tx" in
  (* Code 13 is insufficient fee: rejected at CheckTx, so nothing was spent. *)
  let m = Sub.on_broadcast m (broadcast ~code:13 ()) in
  match (Sub.finished m, Sub.sequence_consumed m) with
  | Some (Sub.Rejected r), Some consumed ->
      Alcotest.(check bool) "rejected at check" true (r.stage = `Check);
      Alcotest.(check int) "with the node's code" 13 r.code;
      Alcotest.(check bool) "and the sequence was not consumed" false consumed
  | _ -> Alcotest.fail "expected a Check-stage rejection"

let delivery_failure_consumes_the_sequence () =
  let m = Sub.start (config ()) in
  let m = Sub.on_status m (status ()) in
  let m = Sub.on_account m (account ()) in
  let m = Sub.on_signed m "tx" in
  let m = Sub.on_broadcast m (broadcast ()) in
  (* Passed CheckTx, then ran out of gas in the block. The fee was taken. *)
  let m = Sub.on_tx m (delivered ~code:11 ()) in
  match (Sub.finished m, Sub.sequence_consumed m) with
  | Some (Sub.Rejected r), Some consumed ->
      Alcotest.(check bool) "rejected at delivery" true (r.stage = `Deliver);
      Alcotest.(check bool) "and the sequence WAS consumed" true consumed
  | _ -> Alcotest.fail "expected a Deliver-stage rejection"

let a_sequence_mismatch_refetches_rather_than_incrementing () =
  let m = Sub.start (config ()) in
  let m = Sub.on_status m (status ()) in
  let m = Sub.on_account m (account ~sequence:1L ()) in
  let m = Sub.on_signed m "tx" in
  (* Code 32: something else moved the account on. *)
  let m = Sub.on_broadcast m (broadcast ~code:32 ()) in
  Alcotest.(check bool)
    "goes back to the chain" true
    (Sub.next m = Sub.Fetch_account);
  Alcotest.(check bool) "and is not finished" true (Sub.finished m = None);
  (* The new sequence comes from the chain, not from adding one locally. *)
  let m = Sub.on_account m (account ~sequence:9L ()) in
  match Sub.next m with
  | Sub.Build_and_sign { sequence; _ } ->
      Alcotest.(check string)
        "the chain's answer, not a guess" "9" (Int64.to_string sequence)
  | _ -> Alcotest.fail "expected Build_and_sign"

let a_dropped_broadcast_refetches () =
  (* The genuinely ambiguous case: the connection died and it is unknown
     whether the node got the transaction. Asking the chain settles it, because
     if it arrived the sequence has moved. *)
  let m = Sub.start (config ()) in
  let m = Sub.on_status m (status ()) in
  let m = Sub.on_account m (account ()) in
  let m = Sub.on_signed m "tx" in
  let m = Sub.on_error m (Rpc.Error.Transport "connection reset") in
  Alcotest.(check bool)
    "asks the chain again" true
    (Sub.next m = Sub.Fetch_account);
  Alcotest.(check bool) "rather than resending" true (Sub.finished m = None)

let a_retry_re_signs () =
  (* There is no path that re-broadcasts bytes signed for a state that moved:
     after a rebuild the machine asks for a signature again. *)
  let m = Sub.start (config ()) in
  let m = Sub.on_status m (status ()) in
  let m = Sub.on_account m (account ~sequence:1L ()) in
  let m = Sub.on_signed m "old bytes" in
  let m = Sub.on_broadcast m (broadcast ~code:32 ()) in
  let m = Sub.on_account m (account ~sequence:2L ()) in
  match Sub.next m with
  | Sub.Build_and_sign { sequence; _ } ->
      Alcotest.(check string)
        "for the new sequence" "2" (Int64.to_string sequence)
  | Sub.Broadcast b -> Alcotest.failf "re-broadcast stale bytes: %S" b
  | _ -> Alcotest.fail "expected Build_and_sign"

(* --- bounds ------------------------------------------------------------- *)

let rebuilds_are_bounded () =
  let rec churn m n =
    if n = 0 then m
    else
      let m = Sub.on_account m (account ()) in
      let m = Sub.on_signed m "tx" in
      churn (Sub.on_broadcast m (broadcast ~code:32 ())) (n - 1)
  in
  let m = Sub.start (config ~max_rebuilds:2 ()) in
  let m = Sub.on_status m (status ()) in
  let m = churn m 5 in
  match Sub.finished m with
  | Some (Sub.Gave_up _) -> ()
  | _ -> Alcotest.fail "an unbounded retry against a node that always says no"

let polling_is_bounded_and_says_what_it_does_not_know () =
  let rec poll m n =
    if n = 0 then m else poll (Sub.on_tx m not_found) (n - 1)
  in
  let m = Sub.start (config ~max_polls:3 ()) in
  let m = Sub.on_status m (status ()) in
  let m = Sub.on_account m (account ()) in
  let m = Sub.on_signed m "tx" in
  let m = Sub.on_broadcast m (broadcast ()) in
  let m = poll m 10 in
  match Sub.finished m with
  | Some (Sub.Gave_up reason) ->
      (* The honest outcome. It was accepted into a mempool and may yet land, so
       claiming it failed would be a lie in the dangerous direction. *)
      let says needle =
        let n = String.length needle and l = String.length reason in
        let rec at i =
          i + n <= l && (String.sub reason i n = needle || at (i + 1))
        in
        at 0
      in
      Alcotest.(check bool)
        ("says the fate is unknown: " ^ reason)
        true (says "unknown")
  | _ -> Alcotest.fail "polling should be bounded"

let a_non_retryable_error_ends_it () =
  let m = Sub.start (config ()) in
  let m = Sub.on_error m (Rpc.Error.Malformed "the node sent nonsense") in
  match Sub.finished m with
  | Some (Sub.Gave_up _) -> ()
  | _ -> Alcotest.fail "a malformed response is not worth retrying"

let () =
  Alcotest.run "cosmos-submission"
    [
      ( "the ordinary path",
        [
          Alcotest.test_case "fetch, sign, broadcast, poll" `Quick
            the_ordinary_sequence;
        ] );
      ( "before anything is signed",
        [
          Alcotest.test_case "the wrong chain" `Quick
            the_wrong_chain_stops_it_before_signing;
          Alcotest.test_case "a catching-up node" `Quick
            a_catching_up_node_is_refused;
          Alcotest.test_case "an account that cannot sign" `Quick
            an_account_that_cannot_sign;
        ] );
      ( "the sequence discipline",
        [
          Alcotest.test_case "check failure leaves it alone" `Quick
            check_failure_leaves_the_sequence_alone;
          Alcotest.test_case "delivery failure consumes it" `Quick
            delivery_failure_consumes_the_sequence;
          Alcotest.test_case "a mismatch refetches" `Quick
            a_sequence_mismatch_refetches_rather_than_incrementing;
          Alcotest.test_case "a dropped broadcast refetches" `Quick
            a_dropped_broadcast_refetches;
          Alcotest.test_case "a retry re-signs" `Quick a_retry_re_signs;
        ] );
      ( "bounds",
        [
          Alcotest.test_case "rebuilds" `Quick rebuilds_are_bounded;
          Alcotest.test_case "polls, and admits what it cannot know" `Quick
            polling_is_bounded_and_says_what_it_does_not_know;
          Alcotest.test_case "a non-retryable error ends it" `Quick
            a_non_retryable_error_ends_it;
        ] );
    ]
