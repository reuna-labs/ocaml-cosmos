(* The umbrella.

   Everything here goes through the [cosmos] library rather than the individual
   packages, which is how a consumer sees it. The point is that the offline
   surface is complete on its own: a transaction can be built, signed, framed,
   decoded and verified without any transport being linked. *)

let ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "expected Ok, got Error %S" e

let unhex h =
  String.init
    (String.length h / 2)
    (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2)))

let end_to_end_with_no_transport () =
  let open Cosmos in
  let profile = Types.Profile.cosmos_hub in
  let base = Types.Profile.base_prefix profile in
  (* A key, and the address it controls. *)
  let key =
    ok (Crypto.private_key_of_bytes (unhex (String.make 62 '0' ^ "01")))
  in
  let pk = Crypto.public_key_of_private key in
  let me =
    ok
      (Types.Address.of_bytes
         (Types.Profile.account_prefix profile)
         (Crypto.address_bytes pk))
  in
  Alcotest.(check string)
    "the address is the one BIP-173 uses"
    "cosmos1w508d6qejxtdg4y5r3zarvary0c5xw7k6ah60c"
    (Types.Address.to_bech32 me);
  (* A transfer to someone else. *)
  let you =
    ok
      (Types.Address.of_bech32 ~base
         "cosmos1q6hag67dl53wl99vzg42z8eyzfz2xlkvsrxukv")
  in
  let body =
    ok
      (Tx.Body.make
         ~messages:
           [
             Tx.Msg.Send
               {
                 from_address = me;
                 to_address = you;
                 amount =
                   [
                     ok (Types.Coin.of_strings ~denom:"uatom" ~amount:"1000000");
                   ];
               };
           ]
         ())
  in
  (* A fee quoted from the profile rather than guessed. *)
  let gas = ok (Types.Amount.of_string "200000") in
  let fee_coin = ok (Types.Profile.fee_for_gas profile ~gas) in
  Alcotest.(check string)
    "the profile quotes the fee" "1000uatom"
    (Types.Coin.to_string fee_coin);
  let auth_info =
    ok
      (Tx.Auth_info.make
         ~signers:
           [
             {
               public_key = Some (Tx.Auth_info.Secp256k1 pk);
               mode = Tx.Auth_info.Direct;
               sequence = 3L;
             };
           ]
         ~fee:
           {
             amount = [ fee_coin ];
             gas_limit = 200_000L;
             payer = None;
             granter = None;
           })
  in
  let chain_id = Types.Profile.chain_id profile in
  let tx =
    ok (Tx.Tx.sign ~body ~auth_info ~chain_id ~account_number:12L ~key)
  in
  (* It verifies, it round-trips, and the hash is the one a node would index. *)
  Alcotest.(check bool)
    "verifies" true
    (Tx.Tx.verify tx ~chain_id ~account_number:12L);
  let decoded = ok (Tx.Tx.of_bytes ~base (Tx.Tx.to_bytes tx)) in
  Alcotest.(check string)
    "round trips" (Tx.Tx.to_bytes tx) (Tx.Tx.to_bytes decoded);
  Alcotest.(check int) "the hash is 32 bytes" 32 (String.length (Tx.Tx.hash tx));
  (* And what it says it does is what it does. *)
  match Tx.Body.messages (Tx.Tx.body decoded) with
  | [ Tx.Msg.Send s ] ->
      Alcotest.(check string)
        "to"
        (Types.Address.to_bech32 you)
        (Types.Address.to_bech32 s.to_address);
      Alcotest.(check string)
        "amount" "1000000uatom"
        (Types.Coin.to_string (List.hd s.amount))
  | _ -> Alcotest.fail "expected one MsgSend"

let confirmation_is_not_boolean () =
  (* Not L2, but it lives in the umbrella and the type is the point: "in a
     mempool" and "delivered" are different answers. This fails if someone
     collapses the variant. *)
  let states =
    Cosmos.Rpc.Confirmation.
      [
        Unknown;
        In_mempool;
        Delivered { height = 1L };
        Final { height = 1L; depth = 6 };
        Failed { code = 5; codespace = "sdk"; log = "insufficient funds" };
      ]
  in
  Alcotest.(check int) "five distinguishable states" 5 (List.length states)

let () =
  Alcotest.run "cosmos"
    [
      ( "umbrella",
        [
          Alcotest.test_case "build, sign and verify with no transport" `Quick
            end_to_end_with_no_transport;
          Alcotest.test_case "confirmation is tagged" `Quick
            confirmation_is_not_boolean;
        ] );
    ]
