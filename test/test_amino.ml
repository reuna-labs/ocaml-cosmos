(* SIGN_MODE_LEGACY_AMINO_JSON, against the SDK's own encoder.

   The fixtures in conformance/fixtures/amino are produced by
   conformance/simd, which runs cosmos-sdk v0.55.0's x/tx/signing/aminojson
   handler -- the encoder a node verifies against. Not legacytx.StdSignBytes,
   which is deprecated upstream and drives the encoding from Go struct tags
   rather than from the amino.* options in the schema; the two can disagree.

   This is the one part of the transaction layer that could not be written
   from the schema alone. Three of its rules were established from the SDK's
   output and would have been guessed wrong:

     - timeout_height appears at the top level of the document as well as in
       the body;
     - CosmWasm's msg is spliced in as JSON and re-serialised, which sorts its
       keys, so a call written {"recipient":..,"amount":..} signs as
       {"amount":..,"recipient":..};
     - dont_omitempty keeps several list and message fields that would
       otherwise vanish when empty. *)

module Tx = Cosmos_tx
module Msg = Tx.Msg
module Body = Tx.Body
module Auth_info = Tx.Auth_info
module Amino = Tx.Amino_json
module Types = Cosmos_types
module Address = Types.Address
module Coin = Types.Coin

let ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "expected Ok, got Error %S" e

let is_error what = function
  | Error _ -> ()
  | Ok _ -> Alcotest.failf "expected %s to be rejected, it was accepted" what

let unhex h =
  String.init
    (String.length h / 2)
    (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2)))

let fixture name =
  let path = Filename.concat "../conformance/fixtures/amino" (name ^ ".json") in
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let addr s = ok (Address.of_bech32 ~base:"cosmos" s)
let coin denom amount = ok (Coin.of_strings ~denom ~amount)
let key1 = "cosmos1w508d6qejxtdg4y5r3zarvary0c5xw7k6ah60c"
let key2 = "cosmos1q6hag67dl53wl99vzg42z8eyzfz2xlkvsrxukv"
let key3 = "cosmos10ht9tyks4vh7p5p904t340cr9nvahy7u8e84x9"

(* The same constants conformance/simd uses. *)
let chain_id = ok (Types.Chain_id.of_string "cosmoshub-4")
let account_number = 42L
let memo = "sent by ocaml-cosmos"
let timeout_height = 20_000_000L

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
             mode = Auth_info.Legacy_amino_json;
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

let sign_bytes messages =
  let body = ok (Body.make ~messages ~memo ~timeout_height ()) in
  ok
    (Amino.sign_bytes ~body ~auth_info:(auth_info ()) ~chain_id ~account_number)

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

(* Deliberately written with the keys in the order a human would type them --
   recipient before amount. The SDK re-sorts them, and this is the case that
   proves we do too. *)
let msg_execute () =
  Msg.Wasm_execute
    {
      sender = addr key1;
      contract = addr key2;
      msg =
        {|{"transfer":{"recipient":"cosmos10ht9tyks4vh7p5p904t340cr9nvahy7u8e84x9","amount":"250"}}|};
      funds = [ coin "uatom" "1" ];
    }

let matches_the_sdk () =
  List.iter
    (fun (name, messages) ->
      Alcotest.(check string) name (fixture name) (sign_bytes messages))
    [
      ("send", [ msg_send () ]);
      ("multi_send", [ msg_multi_send () ]);
      ("transfer", [ msg_transfer () ]);
      ("execute", [ msg_execute () ]);
      ("two_msgs", [ msg_send (); msg_send () ]);
    ]

let the_contract_call_is_resorted () =
  (* Stated separately from the byte comparison because it is the rule most
     likely to be "fixed" by someone who thinks passing the caller's bytes
     through untouched is more faithful. It is not: the node re-serialises. *)
  let out = sign_bytes [ msg_execute () ] in
  let contains needle =
    let n = String.length needle and m = String.length out in
    let rec at i = i + n <= m && (String.sub out i n = needle || at (i + 1)) in
    at 0
  in
  Alcotest.(check bool)
    "amount comes before recipient, as the SDK sorts it" true
    (contains {|{"amount":"250","recipient":|});
  Alcotest.(check bool)
    "and not in the order it was written" false
    (contains {|{"recipient":|}
    && contains
         {|"recipient":"cosmos10ht9tyks4vh7p5p904t340cr9nvahy7u8e84x9","amount"|}
    )

let the_document_is_canonical () =
  let out = sign_bytes [ msg_send () ] in
  (* No whitespace between tokens. Not "no spaces at all": the memo is
     "sent by ocaml-cosmos" and its spaces are content. *)
  let contains needle =
    let n = String.length needle and m = String.length out in
    let rec at i = i + n <= m && (String.sub out i n = needle || at (i + 1)) in
    at 0
  in
  List.iter
    (fun sep ->
      Alcotest.(check bool)
        (Printf.sprintf "no %S between tokens" sep)
        false (contains sep))
    [ "\": "; ", "; "{ "; " }"; "[ "; " ]"; "\n"; "\t" ];
  (* Top-level keys in sorted order. *)
  let expected_prefix =
    {|{"account_number":"42","chain_id":"cosmoshub-4","fee":|}
  in
  Alcotest.(check string)
    "sorted from the first key" expected_prefix
    (String.sub out 0 (String.length expected_prefix));
  (* Numbers are strings, not JSON numbers. *)
  Alcotest.(check bool)
    "account_number is a string" true
    (String.length out > 20
    && String.sub out 1 22 = {|"account_number":"42"|} ^ ",");
  (* timeout_height is a top-level field. *)
  Alcotest.(check bool)
    "timeout_height is at the top level" true
    (contains {|,"timeout_height":"20000000"}|})

let what_cannot_be_signed_this_way () =
  (* A message with no amino name has nothing to put in the "type" field. It
     must be refused rather than signed as something else. *)
  let opaque =
    Msg.of_any ~base:"cosmos"
      ~type_url:"/osmosis.gamm.v1beta1.MsgSwapExactAmountIn" ~value:""
  in
  is_error "an opaque message" (Amino.amino_name opaque);
  let body = ok (Body.make ~messages:[ opaque ] ()) in
  is_error "a body containing one"
    (Amino.sign_bytes ~body ~auth_info:(auth_info ()) ~chain_id ~account_number);
  (* A multi-signer transaction cannot be represented: the document holds one
     sequence, so signing it for the first signer would assert something about
     the others that is not true. *)
  let two =
    ok
      (Auth_info.make
         ~signers:
           [
             {
               public_key = None;
               mode = Auth_info.Legacy_amino_json;
               sequence = 1L;
             };
             {
               public_key = None;
               mode = Auth_info.Legacy_amino_json;
               sequence = 2L;
             };
           ]
         ~fee:
           {
             amount = [ coin "uatom" "1000" ];
             gas_limit = 200_000L;
             payer = None;
             granter = None;
           })
  in
  let body = ok (Body.make ~messages:[ msg_send () ] ()) in
  is_error "two signers"
    (Amino.sign_bytes ~body ~auth_info:two ~chain_id ~account_number)

let the_amino_names_come_from_the_schema () =
  List.iter
    (fun (m, expected) ->
      Alcotest.(check string) expected expected (ok (Amino.amino_name m)))
    [
      (msg_send (), "cosmos-sdk/MsgSend");
      (msg_multi_send (), "cosmos-sdk/MsgMultiSend");
      (* Note: cosmos-sdk/, not ibc/, despite the message living in ibc-go. *)
      (msg_transfer (), "cosmos-sdk/MsgTransfer");
      (msg_execute (), "wasm/MsgExecuteContract");
    ]

let two_modes_two_documents () =
  (* The same transaction under both sign modes produces different bytes and
     different digests. Obvious, and worth pinning: a signer that computed one
     and labelled it the other would be signing the wrong thing. *)
  let body =
    ok (Body.make ~messages:[ msg_send () ] ~memo ~timeout_height ())
  in
  let auth_info = auth_info () in
  let direct =
    Tx.Sign_doc.digest
      (Tx.Sign_doc.make ~body ~auth_info ~chain_id ~account_number)
  in
  let amino = ok (Amino.digest ~body ~auth_info ~chain_id ~account_number) in
  Alcotest.(check int) "both are 32 bytes" 32 (String.length direct);
  Alcotest.(check int) "both are 32 bytes" 32 (String.length amino);
  Alcotest.(check bool) "and they differ" false (String.equal direct amino)

let () =
  Alcotest.run "cosmos-amino"
    [
      ( "against the SDK",
        [
          Alcotest.test_case "the five documents" `Quick matches_the_sdk;
          Alcotest.test_case "the contract call is re-sorted" `Quick
            the_contract_call_is_resorted;
          Alcotest.test_case "amino names come from the schema" `Quick
            the_amino_names_come_from_the_schema;
        ] );
      ( "canonical form",
        [
          Alcotest.test_case "sorted, unspaced, stringly numbered" `Quick
            the_document_is_canonical;
        ] );
      ( "refused",
        [
          Alcotest.test_case "what cannot be signed this way" `Quick
            what_cannot_be_signed_this_way;
          Alcotest.test_case "two modes, two documents" `Quick
            two_modes_two_documents;
        ] );
    ]
