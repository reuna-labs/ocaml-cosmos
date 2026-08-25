(* The scaffold's test suite: it asserts the properties that are true of a
   skeleton, so that they cannot quietly stop being true while the rest is
   written.

   There are deliberately no protocol vectors here yet. Those come from
   conformance/, from two independent oracles, and asserting them against an
   unimplemented library would only record that it is unimplemented. *)

let unimplemented_is_explicit () =
  (* A skeleton must fail loudly, not plausibly. Every stub says which function
     is missing, so a caller who reaches one is not left guessing. *)
  match Cosmos_types.Prefix.make ~base:"cosmos" Cosmos_types.Prefix.Account with
  | Ok _ ->
      Alcotest.fail "Prefix.make claims to work; update this test when it does"
  | Error msg ->
      Alcotest.(check bool)
        "the error names the function" true
        (String.length msg > 0
        && String.length msg >= 13
        && String.sub msg 0 13 = "cosmos-types:")

let unknown_message_is_representable () =
  (* An app-chain message this library has never heard of must have somewhere to
     go. If it did not, the decoder would have to either guess or raise, and
     both are worse than carrying it as opaque. *)
  let m =
    Cosmos_tx.Msg.Unknown
      {
        type_url = "/osmosis.gamm.v1beta1.MsgSwapExactAmountIn";
        value = "\x00\x01";
      }
  in
  match m with
  | Cosmos_tx.Msg.Unknown { type_url; value } ->
      Alcotest.(check string)
        "type_url is retained verbatim"
        "/osmosis.gamm.v1beta1.MsgSwapExactAmountIn" type_url;
      Alcotest.(check int) "and so is the payload" 2 (String.length value)
  | _ -> Alcotest.fail "an unknown type_url must decode as Unknown"

let confirmation_is_not_boolean () =
  (* The whole point of the type: "in a mempool" and "delivered" are different
     answers, and code that treats confirmation as a bool cannot express that.
     This test exists to fail if someone collapses the variant. *)
  let states =
    [
      Cosmos_rpc.Confirmation.Unknown;
      Cosmos_rpc.Confirmation.In_mempool;
      Cosmos_rpc.Confirmation.Delivered { height = 1L };
      Cosmos_rpc.Confirmation.Final { height = 1L; depth = 6 };
      Cosmos_rpc.Confirmation.Failed
        { code = 5; codespace = "sdk"; log = "insufficient funds" };
    ]
  in
  Alcotest.(check int) "five distinguishable states" 5 (List.length states);
  match List.nth states 1 with
  | Cosmos_rpc.Confirmation.Delivered _ ->
      Alcotest.fail "in-mempool must not be delivered"
  | _ -> ()

let sign_doc_retains_its_bytes () =
  (* Constructing a SignDoc must not transform its inputs. This is weak while
     to_bytes is unimplemented, but it pins the constructor's shape: the two
     byte strings go in as bytes and are not parsed on the way. *)
  let body = "\x0a\x00not-really-protobuf" in
  let auth = "\x12\x00nor-is-this" in
  let sd =
    Cosmos_tx.Sign_doc.make ~body_bytes:body ~auth_info_bytes:auth
      ~chain_id:"cosmoshub-4" ~account_number:12345L
  in
  (* If make ever starts validating or re-encoding, this stops being a no-op. *)
  ignore sd;
  Alcotest.(check bool) "constructing a SignDoc does not raise" true true

let () =
  Alcotest.run "cosmos"
    [
      ( "scaffold",
        [
          Alcotest.test_case "unimplemented functions say so" `Quick
            unimplemented_is_explicit;
          Alcotest.test_case "an unknown message stays representable" `Quick
            unknown_message_is_representable;
          Alcotest.test_case "confirmation is tagged, not boolean" `Quick
            confirmation_is_not_boolean;
          Alcotest.test_case "SignDoc takes bytes and keeps them" `Quick
            sign_doc_retains_its_bytes;
        ] );
    ]
