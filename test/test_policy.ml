(* Intent and policy.

   These have no external oracle, and cannot: no other implementation decides
   what this signer will approve. What they do have is a property that can be
   stated exactly -- the intent is derived from the bytes that will be signed,
   not from what the builder said -- and that property is testable by making
   the two disagree. *)

module Tx = Cosmos_tx
module Msg = Tx.Msg
module Body = Tx.Body
module Auth_info = Tx.Auth_info
module Intent = Tx.Intent
module Policy = Tx.Policy
module Types = Cosmos_types
module Address = Types.Address
module Amount = Types.Amount
module Coin = Types.Coin
module Denom = Types.Denom

let ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "expected Ok, got Error %S" e

let addr s = ok (Address.of_bech32 ~base:"cosmos" s)
let coin denom amount = ok (Coin.of_strings ~denom ~amount)
let denom d = ok (Denom.of_string d)
let amount a = ok (Amount.of_string a)
let chain_id = ok (Types.Chain_id.of_string "cosmoshub-4")
let key1 = "cosmos1w508d6qejxtdg4y5r3zarvary0c5xw7k6ah60c"
let key2 = "cosmos1q6hag67dl53wl99vzg42z8eyzfz2xlkvsrxukv"
let key3 = "cosmos10ht9tyks4vh7p5p904t340cr9nvahy7u8e84x9"

let send ?(to_ = key2) ?(amt = "1000000") () =
  Msg.Send
    {
      from_address = addr key1;
      to_address = addr to_;
      amount = [ coin "uatom" amt ];
    }

let auth_info ?(granter = None) ?(gas = 200_000L) ?(fee = "1000") () =
  ok
    (Auth_info.make
       ~signers:
         [ { public_key = None; mode = Auth_info.Direct; sequence = 7L } ]
       ~fee:
         {
           amount = [ coin "uatom" fee ];
           gas_limit = gas;
           payer = None;
           granter;
         })

let intent ?(messages = [ send () ]) ?(memo = "") ?granter () =
  let body = ok (Body.make ~messages ~memo ()) in
  let auth_info = auth_info ?granter () in
  let doc = Tx.Sign_doc.make ~body ~auth_info ~chain_id ~account_number:42L in
  ok (Intent.of_sign_doc ~base:"cosmos" doc)

(* --- derivation --------------------------------------------------------- *)

let intent_comes_from_the_bytes () =
  (* The property, made testable: build a SignDoc whose auth-info bytes are
     from one transaction and whose body bytes are from another, and check
     that the intent describes the bytes rather than anything a builder
     intended. Here the body says 5000000uatom to key3 while the caller was
     nominally sending 1000000 to key2. *)
  let real_body =
    ok
      (Body.make ~messages:[ send ~to_:key3 ~amt:"5000000" () ] ~memo:"real" ())
  in
  let doc =
    Tx.Sign_doc.make ~body:real_body ~auth_info:(auth_info ()) ~chain_id
      ~account_number:42L
  in
  let i = ok (Intent.of_sign_doc ~base:"cosmos" doc) in
  match i.actions with
  | [ Intent.Transfer t ] ->
      Alcotest.(check string)
        "the destination in the bytes" key3
        (Address.to_bech32 t.to_address);
      Alcotest.(check string)
        "the amount in the bytes" "5000000uatom"
        (Coin.to_string (List.hd t.amount));
      Alcotest.(check string) "and the memo" "real" i.memo
  | _ -> Alcotest.fail "expected one transfer"

let everything_that_moves_value_is_a_field () =
  let i = intent ~granter:(Some (addr key3)) ~memo:"note" () in
  Alcotest.(check string)
    "chain" "cosmoshub-4"
    (Types.Chain_id.to_string i.chain_id);
  Alcotest.(check string) "account" "42" (Int64.to_string i.account_number);
  Alcotest.(check string) "sequence" "7" (Int64.to_string i.sequence);
  Alcotest.(check string) "gas" "200000" (Int64.to_string i.gas_limit);
  Alcotest.(check string) "fee" "1000uatom" (Coin.to_string (List.hd i.fee));
  Alcotest.(check bool) "granter is a field" true (i.fee_granter <> None);
  Alcotest.(check string) "memo is a field" "note" i.memo;
  Alcotest.(check int) "signers" 1 i.signer_count;
  Alcotest.(check bool) "fully explainable" true (Intent.is_fully_explainable i)

let an_unreadable_message_is_visible_not_fatal () =
  let opaque =
    Msg.of_any ~base:"cosmos" ~type_url:"/some.chain.v1.MsgUnknown"
      ~value:"\x08\x01"
  in
  let i = intent ~messages:[ send (); opaque ] () in
  Alcotest.(check int) "both actions are present" 2 (List.length i.actions);
  Alcotest.(check bool)
    "and it is not explainable" false
    (Intent.is_fully_explainable i);
  match List.nth i.actions 1 with
  | Intent.Unexplainable u ->
      Alcotest.(check string) "named" "/some.chain.v1.MsgUnknown" u.type_url
  | _ -> Alcotest.fail "expected an unexplainable action"

let rendering_shows_every_field () =
  let i = intent ~granter:(Some (addr key3)) ~memo:"note" () in
  let s = Format.asprintf "%a" Intent.pp i in
  let shows needle =
    let n = String.length needle and m = String.length s in
    let rec at j = j + n <= m && (String.sub s j n = needle || at (j + 1)) in
    Alcotest.(check bool) ("shows " ^ needle) true (at 0)
  in
  shows "cosmoshub-4";
  shows "sequence 7";
  shows "1000uatom for 200000 gas";
  shows "fee granter";
  shows "someone else pays";
  shows key2;
  shows "note"

(* --- policy ------------------------------------------------------------- *)

let refused what verdict =
  match verdict with
  | Policy.Approved ->
      Alcotest.failf "expected %s to be refused, it was approved" what
  | Policy.Refused rs ->
      Alcotest.(check bool) (what ^ ": gives a reason") true (rs <> []);
      rs

let approved what verdict =
  match verdict with
  | Policy.Approved -> ()
  | Policy.Refused rs ->
      Alcotest.failf "expected %s to be approved, refused because: %s" what
        (String.concat "; " rs)

let strict_permits_nothing () =
  let reasons =
    refused "the strict policy" (Policy.review Policy.strict (intent ()))
  in
  (* It refuses for several independent reasons, and says all of them. *)
  Alcotest.(check bool) "more than one reason" true (List.length reasons > 1)

let a_policy_that_describes_the_product () =
  let p =
    Policy.strict
    |> Policy.allow_chain chain_id
    |> Policy.allow_transfer_to (addr key2)
    |> Policy.allow_denom (denom "uatom")
    |> Policy.max_amount_per_denom (denom "uatom") (amount "2000000")
    |> Policy.max_fee (amount "5000") (denom "uatom")
    |> Policy.max_gas 300_000L
  in
  approved "an ordinary transfer" (Policy.review p (intent ()));
  (* Each constraint refuses on its own. *)
  ignore
    (refused "another destination"
       (Policy.review p (intent ~messages:[ send ~to_:key3 () ] ())));
  ignore
    (refused "an amount over the limit"
       (Policy.review p (intent ~messages:[ send ~amt:"3000000" () ] ())));
  ignore (refused "a memo" (Policy.review p (intent ~memo:"hello" ())));
  ignore
    (refused "a fee granter"
       (Policy.review p (intent ~granter:(Some (addr key3)) ())));
  (* Another chain, same everything else. *)
  let other = ok (Types.Chain_id.of_string "cosmoshub-testnet") in
  let body = ok (Body.make ~messages:[ send () ] ()) in
  let doc =
    Tx.Sign_doc.make ~body ~auth_info:(auth_info ()) ~chain_id:other
      ~account_number:42L
  in
  ignore
    (refused "another chain"
       (Policy.review p (ok (Intent.of_sign_doc ~base:"cosmos" doc))))

let a_missing_fee_limit_is_itself_a_refusal () =
  (* A fee is the one amount an attacker can inflate without changing where
     anything goes, so a policy with no ceiling on it is incomplete rather
     than permissive. *)
  let p =
    Policy.strict
    |> Policy.allow_chain chain_id
    |> Policy.allow_transfer_to (addr key2)
    |> Policy.allow_denom (denom "uatom")
  in
  let reasons = refused "no fee limit" (Policy.review p (intent ())) in
  Alcotest.(check bool)
    "and says so" true
    (List.exists
       (fun r ->
         let needle = "no fee limit" in
         let n = String.length needle and m = String.length r in
         let rec at i =
           i + n <= m && (String.sub r i n = needle || at (i + 1))
         in
         at 0)
       reasons)

let what_is_never_approved () =
  let p =
    Policy.strict
    |> Policy.allow_chain chain_id
    |> Policy.allow_transfer_to (addr key2)
    |> Policy.allow_denom (denom "uatom")
    |> Policy.max_fee (amount "5000") (denom "uatom")
    |> Policy.allow_multiple_actions
  in
  (* An opaque message. *)
  let opaque =
    Msg.of_any ~base:"cosmos" ~type_url:"/x.v1.MsgUnknown" ~value:""
  in
  ignore
    (refused "an opaque message"
       (Policy.review p (intent ~messages:[ opaque ] ())));
  (* A contract call: the payload is opaque and no policy here can read it. *)
  let call =
    Msg.Wasm_execute
      {
        sender = addr key1;
        contract = addr key2;
        msg = {|{"a":1}|};
        funds = [];
      }
  in
  ignore
    (refused "a contract call" (Policy.review p (intent ~messages:[ call ] ())));
  (* An IBC transfer: the destination is on a chain this policy cannot check. *)
  let ibc =
    Msg.Ibc_transfer
      {
        source_port = "transfer";
        source_channel = "channel-141";
        token = coin "uatom" "1";
        sender = addr key1;
        receiver = "osmo1w508d6qejxtdg4y5r3zarvary0c5xw7kdjmmmt";
        timeout_height = { revision_number = 1L; revision_height = 1L };
        timeout_timestamp = 1L;
        memo = "";
      }
  in
  ignore
    (refused "an ibc transfer" (Policy.review p (intent ~messages:[ ibc ] ())));
  (* A multi-send. *)
  let multi =
    Msg.Multi_send
      {
        inputs = [ { address = addr key1; coins = [ coin "uatom" "1" ] } ];
        outputs = [ { address = addr key2; coins = [ coin "uatom" "1" ] } ];
      }
  in
  ignore
    (refused "a multi-send" (Policy.review p (intent ~messages:[ multi ] ())))

let batching_is_off_by_default () =
  let p =
    Policy.strict
    |> Policy.allow_chain chain_id
    |> Policy.allow_transfer_to (addr key2)
    |> Policy.allow_denom (denom "uatom")
    |> Policy.max_fee (amount "5000") (denom "uatom")
  in
  approved "one transfer" (Policy.review p (intent ()));
  ignore
    (refused "two transfers"
       (Policy.review p (intent ~messages:[ send (); send () ] ())));
  let p = Policy.allow_multiple_actions p in
  approved "two transfers, once permitted"
    (Policy.review p (intent ~messages:[ send (); send () ] ()))

let () =
  Alcotest.run "cosmos-policy"
    [
      ( "intent",
        [
          Alcotest.test_case "derived from the bytes" `Quick
            intent_comes_from_the_bytes;
          Alcotest.test_case "every field is a field" `Quick
            everything_that_moves_value_is_a_field;
          Alcotest.test_case "unreadable is visible, not fatal" `Quick
            an_unreadable_message_is_visible_not_fatal;
          Alcotest.test_case "the rendering hides nothing" `Quick
            rendering_shows_every_field;
        ] );
      ( "policy",
        [
          Alcotest.test_case "strict permits nothing" `Quick
            strict_permits_nothing;
          Alcotest.test_case "one that describes a product" `Quick
            a_policy_that_describes_the_product;
          Alcotest.test_case "a missing fee limit is a refusal" `Quick
            a_missing_fee_limit_is_itself_a_refusal;
          Alcotest.test_case "what is never approved" `Quick
            what_is_never_approved;
          Alcotest.test_case "batching is off by default" `Quick
            batching_is_off_by_default;
        ] );
    ]
