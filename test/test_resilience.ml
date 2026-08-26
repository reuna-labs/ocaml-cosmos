(* The cases L5 names: restart, timeout, stale state, malformed responses, and
   finality.

   These are the ones that are awkward to arrange against a real node and cheap
   to arrange against a pure state machine, which is most of the argument for
   the machine being pure. *)

module Rpc = Cosmos_rpc
module Sub = Rpc.Submission
module Conf = Rpc.Confirmation
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

let config ?(max_rebuilds = 3) ?(max_polls = 5) () =
  { Sub.chain_id = hub; signer; max_rebuilds; max_polls }

let status ?(catching_up = false) ?(height = 32_675_057L) () =
  {
    Rpc.Method.chain_id = hub;
    node_version = "0.38.22";
    latest_block_height = height;
    latest_block_time = "t";
    catching_up;
  }

let account ?(sequence = 1L) () =
  Rpc.Query.Base
    {
      address = signer;
      account_number = 51_199L;
      sequence;
      has_public_key = true;
    }

let broadcast ?(code = 0) ?(hash = "ABCD") () =
  { Rpc.Method.code; codespace = "sdk"; log = ""; hash }

let tx_result ?(code = 0) ?(height = 32_675_050L) () =
  {
    Rpc.Method.hash = "ABCD";
    height;
    code;
    codespace = "sdk";
    log = (if code = 0 then "" else "out of gas");
    gas_wanted = 200_000L;
    gas_used = 78_000L;
  }

let not_found =
  Error (Rpc.Error.Rpc { code = -32603; message = "tx not found" })

(* --- restart ------------------------------------------------------------ *)

let a_restart_resumes_from_the_hash_alone () =
  (* The only thing worth persisting. Everything else is re-derivable from the
     chain and is safer re-derived, because it may have moved while the process
     was down. *)
  let m = Sub.resume (config ()) ~hash:"ABCD" in
  Alcotest.(check bool)
    "goes straight to polling" true
    (Sub.next m = Sub.Poll { hash = "ABCD" });
  Alcotest.(check bool) "and is not finished" true (Sub.finished m = None);
  let m = Sub.on_tx m (Ok (tx_result ())) in
  match Sub.finished m with
  | Some (Sub.Delivered d) ->
      Alcotest.(check string)
        "it went through while we were down" "32675050"
        (Int64.to_string d.height)
  | _ -> Alcotest.fail "expected Delivered"

let a_restart_finds_out_it_never_arrived () =
  (* The other answer, and the reason to resume at all rather than just start
     again: if it never arrived, polling ends and the caller rebuilds. If it
     had arrived and the caller had simply started again, it would be signing a
     second transaction for a sequence the first one already used. *)
  let rec poll m n =
    if n = 0 then m else poll (Sub.on_tx m not_found) (n - 1)
  in
  let m = poll (Sub.resume (config ~max_polls:3 ()) ~hash:"ABCD") 10 in
  match Sub.finished m with
  | Some (Sub.Gave_up reason) ->
      let says needle =
        let n = String.length needle and l = String.length reason in
        let rec at i =
          i + n <= l && (String.sub reason i n = needle || at (i + 1))
        in
        at 0
      in
      Alcotest.(check bool)
        ("admits it does not know: " ^ reason)
        true (says "unknown")
  | _ -> Alcotest.fail "expected Gave_up"

(* --- stale state -------------------------------------------------------- *)

let a_stale_sequence_is_refetched_not_incremented () =
  (* The account moved between the fetch and the broadcast -- something else
     signed for it. The chain's answer is authoritative and a local increment
     would be a guess. *)
  let m = Sub.start (config ()) in
  let m = Sub.on_status m (status ()) in
  let m = Sub.on_account m (account ~sequence:4L ()) in
  let m = Sub.on_signed m "tx" in
  let m = Sub.on_broadcast m (broadcast ~code:32 ()) in
  Alcotest.(check bool)
    "asks the chain again" true
    (Sub.next m = Sub.Fetch_account);
  let m = Sub.on_account m (account ~sequence:11L ()) in
  match Sub.next m with
  | Sub.Build_and_sign { sequence; _ } ->
      Alcotest.(check string)
        "the chain's number, not ours" "11" (Int64.to_string sequence)
  | _ -> Alcotest.fail "expected Build_and_sign"

let a_node_behind_the_chain_is_refused_before_signing () =
  (* A catching-up node's account state is old, so its sequence is old, so
     anything signed against it is stale before it is built. *)
  let m = Sub.start (config ()) in
  let m = Sub.on_status m (status ~catching_up:true ()) in
  match Sub.finished m with
  | Some (Sub.Gave_up _) -> ()
  | _ -> Alcotest.fail "a syncing node should stop it before anything is signed"

(* --- timeout ------------------------------------------------------------ *)

let polling_is_bounded_in_both_directions () =
  (* Bounded whether the node answers "not yet" or fails to answer at all. *)
  let exhaust feed =
    let rec go m n = if n = 0 then m else go (feed m) (n - 1) in
    let m = Sub.start (config ~max_polls:2 ()) in
    let m = Sub.on_status m (status ()) in
    let m = Sub.on_account m (account ()) in
    let m = Sub.on_signed m "tx" in
    go (Sub.on_broadcast m (broadcast ())) 10
  in
  (match Sub.finished (exhaust (fun m -> Sub.on_tx m not_found)) with
  | Some (Sub.Gave_up _) -> ()
  | _ -> Alcotest.fail "polling a node that says 'not yet' must be bounded");
  match
    Sub.finished
      (exhaust (fun m -> Sub.on_error m (Rpc.Error.Transport "timed out")))
  with
  | Some (Sub.Gave_up _) -> ()
  | _ -> Alcotest.fail "polling a node that does not answer must be bounded"

let rebuilding_is_bounded () =
  let rec churn m n =
    if n = 0 then m
    else
      let m = Sub.on_account m (account ()) in
      let m = Sub.on_signed m "tx" in
      churn (Sub.on_broadcast m (broadcast ~code:32 ())) (n - 1)
  in
  let m = Sub.start (config ~max_rebuilds:2 ()) in
  let m = churn (Sub.on_status m (status ())) 6 in
  match Sub.finished m with
  | Some (Sub.Gave_up _) -> ()
  | _ -> Alcotest.fail "an unbounded rebuild against a node that always says no"

(* --- malformed responses ------------------------------------------------ *)

let a_malformed_response_ends_it_rather_than_looping () =
  (* Retrying a node that is speaking a different protocol is a way to do
     nothing repeatedly. Only transport failures are worth another attempt. *)
  List.iter
    (fun (what, e) ->
      let m = Sub.on_error (Sub.start (config ())) e in
      match Sub.finished m with
      | Some (Sub.Gave_up _) -> ()
      | _ -> Alcotest.failf "%s should end it" what)
    [
      ("a malformed response", Rpc.Error.Malformed "not what the protocol says");
      ( "an rpc error",
        Rpc.Error.Rpc { code = -32601; message = "Method not found" } );
      ( "an abci error",
        Rpc.Error.Abci { code = 18; codespace = "sdk"; log = "" } );
    ];
  (* ... and a transport failure is not one of them. *)
  let m = Sub.on_error (Sub.start (config ())) (Rpc.Error.Transport "reset") in
  Alcotest.(check bool)
    "a transport failure is retried" true
    (Sub.finished m = None)

(* --- finality ----------------------------------------------------------- *)

let a_broadcast_can_never_be_delivered () =
  (* The type makes the commonest mistake unrepresentable: of_broadcast has no
     branch that produces Delivered or Final. *)
  (match Conf.of_broadcast (broadcast ()) with
  | Conf.In_mempool -> ()
  | c -> Alcotest.failf "a code-0 broadcast became %a" Conf.pp c);
  Alcotest.(check bool)
    "and in a mempool is not settled" false
    (Conf.is_settled (Conf.of_broadcast (broadcast ())));
  match Conf.of_broadcast (broadcast ~code:13 ()) with
  | Conf.Failed f -> Alcotest.(check int) "the node's code" 13 f.code
  | c -> Alcotest.failf "a failed broadcast became %a" Conf.pp c

let depth_is_distrust_of_the_node_not_consensus () =
  (* CometBFT has instant finality: a committed block is committed. Depth here
     measures how much a product distrusts the node reporting it, which is why
     required_depth is the caller's and has no default. *)
  let r = tx_result ~height:32_675_050L () in
  let tip = 32_675_057L in
  (* Seven deep. Against a node you run, zero is defensible. *)
  (match Conf.of_tx r ~tip ~required_depth:0 with
  | Conf.Final f -> Alcotest.(check int) "depth" 7 f.depth
  | c -> Alcotest.failf "expected Final, got %a" Conf.pp c);
  (match Conf.of_tx r ~tip ~required_depth:7 with
  | Conf.Final _ -> ()
  | c ->
      Alcotest.failf "exactly at the requirement should be final, got %a"
        Conf.pp c);
  (* One more than there is: delivered, not final. *)
  match Conf.of_tx r ~tip ~required_depth:8 with
  | Conf.Delivered d ->
      Alcotest.(check string) "height" "32675050" (Int64.to_string d.height)
  | c -> Alcotest.failf "expected Delivered, got %a" Conf.pp c

let a_node_that_contradicts_itself_is_believed_less () =
  (* A height above the node's own tip. Believing the larger number and calling
     it deeply confirmed would be exactly backwards. *)
  let r = tx_result ~height:32_675_100L () in
  match Conf.of_tx r ~tip:32_675_057L ~required_depth:0 with
  | Conf.Delivered _ -> ()
  | c -> Alcotest.failf "expected Delivered, got %a" Conf.pp c

let a_delivered_failure_is_settled () =
  (* It landed in a block and the application rejected it. The fee was taken
     and the sequence consumed, so there is nothing to wait for. *)
  let c =
    Conf.of_tx (tx_result ~code:11 ()) ~tip:32_675_057L ~required_depth:0
  in
  (match c with
  | Conf.Failed f -> Alcotest.(check int) "code" 11 f.code
  | c -> Alcotest.failf "expected Failed, got %a" Conf.pp c);
  Alcotest.(check bool) "settled" true (Conf.is_settled c);
  Alcotest.(check bool) "but not final" false (Conf.is_final c)

let the_states_read_differently () =
  let says c needle =
    let s = Format.asprintf "%a" Conf.pp c in
    let n = String.length needle and m = String.length s in
    let rec at i = i + n <= m && (String.sub s i n = needle || at (i + 1)) in
    Alcotest.(check bool) (s ^ " mentions " ^ needle) true (at 0)
  in
  says Conf.In_mempool "not executed";
  says (Conf.Delivered { height = 1L }) "delivered";
  says (Conf.Final { height = 1L; depth = 6 }) "final";
  says
    (Conf.Failed { code = 5; codespace = "sdk"; log = "insufficient funds" })
    "insufficient funds"

let () =
  Alcotest.run "cosmos-resilience"
    [
      ( "restart",
        [
          Alcotest.test_case "resumes from the hash alone" `Quick
            a_restart_resumes_from_the_hash_alone;
          Alcotest.test_case "finds out it never arrived" `Quick
            a_restart_finds_out_it_never_arrived;
        ] );
      ( "stale state",
        [
          Alcotest.test_case "a stale sequence is refetched" `Quick
            a_stale_sequence_is_refetched_not_incremented;
          Alcotest.test_case "a node behind the chain" `Quick
            a_node_behind_the_chain_is_refused_before_signing;
        ] );
      ( "timeout",
        [
          Alcotest.test_case "polling is bounded both ways" `Quick
            polling_is_bounded_in_both_directions;
          Alcotest.test_case "rebuilding is bounded" `Quick
            rebuilding_is_bounded;
        ] );
      ( "malformed",
        [
          Alcotest.test_case "ends it rather than looping" `Quick
            a_malformed_response_ends_it_rather_than_looping;
        ] );
      ( "finality",
        [
          Alcotest.test_case "a broadcast is never delivered" `Quick
            a_broadcast_can_never_be_delivered;
          Alcotest.test_case "depth is distrust, not consensus" `Quick
            depth_is_distrust_of_the_node_not_consensus;
          Alcotest.test_case "a self-contradicting node" `Quick
            a_node_that_contradicts_itself_is_believed_less;
          Alcotest.test_case "a delivered failure is settled" `Quick
            a_delivered_failure_is_settled;
          Alcotest.test_case "the states read differently" `Quick
            the_states_read_differently;
        ] );
    ]
