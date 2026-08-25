(* Transaction construction, against protoc.

   The fixtures in conformance/fixtures/protoc are produced by protoc itself --
   the C++ reference implementation of the format, sharing nothing with
   ocaml-protoc-plugin. Agreeing with it establishes that these bytes are what
   the format says. Round-tripping through our own encoder could not.

   conformance/protoc/*.txtpb is the reviewable half: it says what each
   transaction is, in text, and the .hex says what it serialises to. *)

module Tx = Cosmos_tx
module Msg = Tx.Msg
module Body = Tx.Body
module Auth_info = Tx.Auth_info
module Sign_doc = Tx.Sign_doc
module Types = Cosmos_types
module Address = Types.Address
module Coin = Types.Coin
module Prefix = Types.Prefix

let ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "expected Ok, got Error %S" e

let is_error what = function
  | Error _ -> ()
  | Ok _ -> Alcotest.failf "expected %s to be rejected, it was accepted" what

let hex s =
  String.concat ""
    (List.map
       (fun c -> Printf.sprintf "%02x" (Char.code c))
       (List.init (String.length s) (String.get s)))

let unhex h =
  String.init
    (String.length h / 2)
    (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2)))

(* dune copies conformance/ into the build tree; see the root dune. *)
let fixture name =
  let path = Filename.concat "../conformance/fixtures/protoc" (name ^ ".hex") in
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  String.trim s

let addr s = ok (Address.of_bech32 ~base:"cosmos" s)
let coin denom amount = ok (Coin.of_strings ~denom ~amount)
let key1 = "cosmos1w508d6qejxtdg4y5r3zarvary0c5xw7k6ah60c"
let key2 = "cosmos1q6hag67dl53wl99vzg42z8eyzfz2xlkvsrxukv"
let key3 = "cosmos10ht9tyks4vh7p5p904t340cr9nvahy7u8e84x9"

(* --- the four messages -------------------------------------------------- *)

let msg_send () =
  Msg.Send
    {
      from_address = addr key1;
      to_address = addr key2;
      amount = [ coin "uatom" "1000000" ];
    }

let msg_multi_send () =
  Msg.Multi_send
    {
      inputs = [ { address = addr key1; coins = [ coin "uatom" "3000000" ] } ];
      outputs =
        [
          { address = addr key2; coins = [ coin "uatom" "1000000" ] };
          { address = addr key3; coins = [ coin "uatom" "2000000" ] };
        ];
    }

let msg_transfer () =
  Msg.Ibc_transfer
    {
      source_port = "transfer";
      source_channel = "channel-141";
      token = coin "uatom" "500000";
      sender = addr key1;
      receiver = "osmo1w508d6qejxtdg4y5r3zarvary0c5xw7kdjmmmt";
      timeout_height = { revision_number = 1L; revision_height = 20_000_000L };
      timeout_timestamp = 1_774_000_000_000_000_000L;
      memo = "";
    }

let msg_execute () =
  Msg.Wasm_execute
    {
      sender = addr key1;
      contract = addr key2;
      msg =
        {|{"transfer":{"recipient":"cosmos10ht9tyks4vh7p5p904t340cr9nvahy7u8e84x9","amount":"250"}}|};
      funds = [ coin "uatom" "1" ];
    }

let messages_match_protoc () =
  List.iter
    (fun (name, m) ->
      let _, value = ok (Msg.to_any m) in
      Alcotest.(check string) name (fixture name) (hex value))
    [
      ("msg_send", msg_send ());
      ("msg_multi_send", msg_multi_send ());
      ("msg_transfer", msg_transfer ());
      ("msg_execute", msg_execute ());
    ]

let messages_round_trip () =
  List.iter
    (fun (name, m) ->
      let type_url, value = ok (Msg.to_any m) in
      let back = Msg.of_any ~base:"cosmos" ~type_url ~value in
      Alcotest.(check bool)
        (name ^ " is approvable") true (Msg.is_approvable back);
      Alcotest.(check string) (name ^ " type_url") type_url (Msg.type_url back);
      let _, value' = ok (Msg.to_any back) in
      Alcotest.(check string)
        (name ^ " re-encodes identically")
        (hex value) (hex value'))
    [
      ("msg_send", msg_send ());
      ("msg_multi_send", msg_multi_send ());
      ("msg_transfer", msg_transfer ());
      ("msg_execute", msg_execute ());
    ]

(* --- the envelope ------------------------------------------------------- *)

let body () =
  ok
    (Body.make
       ~messages:[ msg_send () ]
       ~memo:"sent by ocaml-cosmos" ~timeout_height:20_000_000L ())

let auth_info () =
  let pk =
    ok
      (Cosmos_crypto.public_key_of_bytes
         (unhex
            "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"))
  in
  ok
    (Auth_info.make
       ~signers:
         [
           {
             public_key = Some (Auth_info.Secp256k1 pk);
             mode = Auth_info.Direct;
             sequence = 7L;
           };
         ]
       ~fee:
         {
           amount = [ coin "uatom" "1000" ];
           gas_limit = 200_000L;
           payer = None;
           granter = None;
         })

let envelope_matches_protoc () =
  Alcotest.(check string)
    "tx_body" (fixture "tx_body")
    (hex (Body.to_bytes (body ())));
  Alcotest.(check string)
    "auth_info" (fixture "auth_info")
    (hex (Auth_info.to_bytes (auth_info ())));
  let doc =
    Sign_doc.make ~body:(body ()) ~auth_info:(auth_info ())
      ~chain_id:(ok (Types.Chain_id.of_string "cosmoshub-4"))
      ~account_number:42L
  in
  Alcotest.(check string)
    "sign_doc" (fixture "sign_doc")
    (hex (Sign_doc.to_bytes doc))

let the_signed_bytes_are_the_broadcast_bytes () =
  (* The invariant, checked rather than asserted. Build, sign, serialise,
     decode what was serialised, and confirm the body and auth-info bytes came
     back untouched -- then that the signature still verifies against a
     SignDoc rebuilt from them. *)
  let key =
    ok (Cosmos_crypto.private_key_of_bytes (unhex (String.make 62 '0' ^ "01")))
  in
  let chain_id = ok (Types.Chain_id.of_string "cosmoshub-4") in
  let tx =
    ok
      (Tx.Tx.sign ~body:(body ()) ~auth_info:(auth_info ()) ~chain_id
         ~account_number:42L ~key)
  in
  Alcotest.(check bool)
    "it verifies as built" true
    (Tx.Tx.verify tx ~chain_id ~account_number:42L);
  let decoded = ok (Tx.Tx.of_bytes ~base:"cosmos" (Tx.Tx.to_bytes tx)) in
  Alcotest.(check string)
    "body bytes survive the round trip"
    (hex (Body.to_bytes (Tx.Tx.body tx)))
    (hex (Body.to_bytes (Tx.Tx.body decoded)));
  Alcotest.(check string)
    "auth info bytes survive"
    (hex (Auth_info.to_bytes (Tx.Tx.auth_info tx)))
    (hex (Auth_info.to_bytes (Tx.Tx.auth_info decoded)));
  Alcotest.(check string)
    "and so does the whole transaction"
    (hex (Tx.Tx.to_bytes tx))
    (hex (Tx.Tx.to_bytes decoded));
  Alcotest.(check bool)
    "the decoded transaction still verifies" true
    (Tx.Tx.verify decoded ~chain_id ~account_number:42L);
  (* The signature is over the SignDoc, so changing the chain id or account
     number must break it -- that is what binds a transaction to a chain. *)
  Alcotest.(check bool)
    "not on another chain" false
    (Tx.Tx.verify decoded
       ~chain_id:(ok (Types.Chain_id.of_string "cosmoshub-testnet"))
       ~account_number:42L);
  Alcotest.(check bool)
    "not for another account" false
    (Tx.Tx.verify decoded ~chain_id ~account_number:43L)

(* --- what cannot be approved -------------------------------------------- *)

let an_unknown_message_stays_opaque () =
  let m =
    Msg.of_any ~base:"cosmos"
      ~type_url:"/osmosis.gamm.v1beta1.MsgSwapExactAmountIn" ~value:"\x0a\x02hi"
  in
  Alcotest.(check bool) "not approvable" false (Msg.is_approvable m);
  (match m with
  | Msg.Opaque { why; _ } ->
      Alcotest.(check string) "and says why" "unrecognised type_url" why
  | _ -> Alcotest.fail "should be opaque");
  (* It re-emits exactly what it was given: a message this library cannot read
     is one it must not reshape. *)
  let url, value = ok (Msg.to_any m) in
  Alcotest.(check string)
    "type_url kept" "/osmosis.gamm.v1beta1.MsgSwapExactAmountIn" url;
  Alcotest.(check string) "value kept" "\x0a\x02hi" value;
  (* A body containing it is not approvable either. *)
  let b = ok (Body.make ~messages:[ m ] ()) in
  Alcotest.(check bool) "nor is the body" false (Body.is_approvable b)

let a_known_url_with_a_broken_payload () =
  (* Different situation from an unknown type_url, and the reason is kept
     rather than collapsed into the same message. *)
  let m =
    Msg.of_any ~base:"cosmos" ~type_url:"/cosmos.bank.v1beta1.MsgSend"
      ~value:"\xff\xff\xff"
  in
  Alcotest.(check bool) "not approvable" false (Msg.is_approvable m);
  match m with
  | Msg.Opaque { why; _ } ->
      Alcotest.(check bool)
        ("the reason is not 'unrecognised': " ^ why)
        true
        (why <> "unrecognised type_url")
  | _ -> Alcotest.fail "should be opaque"

let an_address_from_another_chain () =
  (* A MsgSend naming osmo1 addresses is well-formed protobuf, and is not a
     transfer the Hub can make. Built by encoding it as an Osmosis message,
     then decoded as a Cosmos one -- which is exactly the paste a user makes.
     It must not come back approvable. *)
  (* Built by re-spelling the Hub addresses under Osmosis's prefix -- the same
     twenty bytes, which is the hazard. Deriving them rather than writing the
     strings out also means no checksum here was invented. *)
  let osmo_prefix = ok (Prefix.make ~base:"osmo" Prefix.Account) in
  let respell a = ok (Address.of_bytes osmo_prefix (Address.to_bytes a)) in
  let from_address = respell (addr key1) and to_address = respell (addr key2) in
  Alcotest.(check bool)
    "same bytes as the Hub address" true
    (Address.same_bytes from_address (addr key1));
  Alcotest.(check bool)
    "and a different address" false
    (Address.equal from_address (addr key1));
  let m_osmo =
    Msg.Send { from_address; to_address; amount = [ coin "uosmo" "1" ] }
  in
  let _, value = ok (Msg.to_any m_osmo) in
  let m =
    Msg.of_any ~base:"cosmos" ~type_url:"/cosmos.bank.v1beta1.MsgSend" ~value
  in
  Alcotest.(check bool) "not approvable on the Hub" false (Msg.is_approvable m);
  (* On its own chain the same bytes read perfectly well. *)
  Alcotest.(check bool)
    "but it is on Osmosis" true
    (Msg.is_approvable
       (Msg.of_any ~base:"osmo" ~type_url:"/cosmos.bank.v1beta1.MsgSend" ~value))

let bodies_that_mean_nothing () =
  is_error "a body with no messages" (Body.make ~messages:[] ());
  (* unordered without a timeout timestamp has no bound on replay at all:
     there is no sequence either. *)
  is_error "unordered with no timeout"
    (Body.make ~messages:[ msg_send () ] ~unordered:true ());
  Alcotest.(check bool)
    "unordered with one is fine" true
    (Result.is_ok
       (Body.make
          ~messages:[ msg_send () ]
          ~unordered:true ~timeout_timestamp:1_774_000_000L ()))

let auth_info_rules () =
  let fee : Auth_info.fee =
    {
      amount = [ coin "uatom" "1000" ];
      gas_limit = 200_000L;
      payer = None;
      granter = None;
    }
  in
  is_error "no signers" (Auth_info.make ~signers:[] ~fee);
  is_error "zero gas"
    (Auth_info.make
       ~signers:
         [ { public_key = None; mode = Auth_info.Direct; sequence = 0L } ]
       ~fee:{ fee with gas_limit = 0L });
  (* A fee granter is authority, and has to be visible. *)
  let delegated =
    ok
      (Auth_info.make
         ~signers:
           [ { public_key = None; mode = Auth_info.Direct; sequence = 0L } ]
         ~fee:{ fee with granter = Some (addr key3) })
  in
  Alcotest.(check bool)
    "delegation is reported" true
    (Auth_info.has_fee_delegation delegated);
  Alcotest.(check bool)
    "and absence is too" false
    (Auth_info.has_fee_delegation (auth_info ()))

let () =
  Alcotest.run "cosmos-tx"
    [
      ( "against protoc",
        [
          Alcotest.test_case "the four messages" `Quick messages_match_protoc;
          Alcotest.test_case "body, auth info and sign doc" `Quick
            envelope_matches_protoc;
        ] );
      ( "the invariant",
        [
          Alcotest.test_case "signed bytes are broadcast bytes" `Quick
            the_signed_bytes_are_the_broadcast_bytes;
          Alcotest.test_case "messages round trip" `Quick messages_round_trip;
        ] );
      ( "unapprovable",
        [
          Alcotest.test_case "an unknown type_url" `Quick
            an_unknown_message_stays_opaque;
          Alcotest.test_case "a known url, broken payload" `Quick
            a_known_url_with_a_broken_payload;
          Alcotest.test_case "an address from another chain" `Quick
            an_address_from_another_chain;
        ] );
      ( "refused at construction",
        [
          Alcotest.test_case "bodies that mean nothing" `Quick
            bodies_that_mean_nothing;
          Alcotest.test_case "auth info rules" `Quick auth_info_rules;
        ] );
    ]
