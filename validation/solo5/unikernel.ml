(* Links the offline closure. What it does at run time matters less than what
   it does at link time, but it touches each package so that none is dropped as
   unreferenced. *)

let () =
  (* Types: a bech32 prefix, which is where the account / validator /
     consensus distinction lives. *)
  (match
     Cosmos_types.Prefix.make ~base:"cosmos" Cosmos_types.Prefix.Account
   with
  | Ok p -> print_endline ("prefix    " ^ Cosmos_types.Prefix.to_string p)
  | Error e -> print_endline ("prefix    not yet: " ^ e));

  (* Tx: a whole transaction, built and signed, with no transport linked. *)
  let key =
    Result.get_ok
      (Cosmos_crypto.private_key_of_bytes
         (String.init 32 (fun i -> if i = 31 then '\x01' else '\x00')))
  in
  let pk = Cosmos_crypto.public_key_of_private key in
  let me =
    Result.get_ok
      (Cosmos_types.Address.of_bytes Cosmos_types.Prefix.cosmos
         (Cosmos_crypto.address_bytes pk))
  in
  print_endline ("address   " ^ Cosmos_types.Address.to_bech32 me);
  let body =
    Result.get_ok
      (Cosmos_tx.Body.make
         ~messages:
           [
             Cosmos_tx.Msg.Send
               {
                 from_address = me;
                 to_address = me;
                 amount =
                   [
                     Result.get_ok
                       (Cosmos_types.Coin.of_strings ~denom:"uatom" ~amount:"1");
                   ];
               };
           ]
         ())
  in
  let auth_info =
    Result.get_ok
      (Cosmos_tx.Auth_info.make
         ~signers:
           [
             {
               public_key = Some (Cosmos_tx.Auth_info.Secp256k1 pk);
               mode = Cosmos_tx.Auth_info.Direct;
               sequence = 0L;
             };
           ]
         ~fee:
           {
             amount =
               [
                 Result.get_ok
                   (Cosmos_types.Coin.of_strings ~denom:"uatom" ~amount:"1000");
               ];
             gas_limit = 200_000L;
             payer = None;
             granter = None;
           })
  in
  let chain_id =
    Result.get_ok (Cosmos_types.Chain_id.of_string "cosmoshub-4")
  in
  let tx =
    Result.get_ok
      (Cosmos_tx.Tx.sign ~body ~auth_info ~chain_id ~account_number:0L ~key)
  in
  Printf.printf "tx        %d bytes\n"
    (String.length (Cosmos_tx.Tx.to_bytes tx));
  Printf.printf "verifies  %b\n"
    (Cosmos_tx.Tx.verify tx ~chain_id ~account_number:0L);

  (* The signer transcript: reviewed, approved, and printed as a human would
     see it. The whole L4 surface links with no transport. *)
  let policy =
    Cosmos_tx.Policy.strict
    |> Cosmos_tx.Policy.allow_chain chain_id
    |> Cosmos_tx.Policy.allow_transfer_to me
    |> Cosmos_tx.Policy.allow_denom
         (Result.get_ok (Cosmos_types.Denom.of_string "uatom"))
    |> Cosmos_tx.Policy.max_fee
         (Result.get_ok (Cosmos_types.Amount.of_string "5000"))
         (Result.get_ok (Cosmos_types.Denom.of_string "uatom"))
  in
  let doc =
    Cosmos_tx.Sign_doc.make ~body ~auth_info ~chain_id ~account_number:0L
  in
  let request =
    Result.get_ok
      (Cosmos_signer.Transcript.request ~chain_id ~account_number:0L
         ~sequence:0L ~sign_mode:Cosmos_signer.Transcript.Direct
         ~payload:(Cosmos_tx.Sign_doc.to_bytes doc)
         ~nonce:(String.make 16 '\x2a') ~not_after:1_800_000_000L)
  in
  (match Cosmos_signer.Transcript.review ~base:"cosmos" ~policy request with
  | Error reasons ->
      List.iter (fun r -> print_endline ("refused   " ^ r)) reasons
  | Ok review -> (
      match
        Cosmos_signer.Transcript.sign review ~key
          ~measurement:"solo5:validation"
      with
      | Error e -> print_endline ("sign      " ^ e)
      | Ok approval ->
          let verified =
            Cosmos_signer.Transcript.verify approval
              ~key:(Cosmos_crypto.public_key_of_private key)
              ~now:1_700_000_000L
          in
          Printf.printf "approved  %b\n" (Result.is_ok verified);
          print_newline ();
          print_endline
            (Format.asprintf "%a" Cosmos_signer.Transcript.pp approval)));

  (* A message this library cannot read is unapprovable, and says so. *)
  let unknown =
    Cosmos_tx.Msg.of_any ~base:"cosmos" ~type_url:"/an.app.chain.v1.MsgWhoKnows"
      ~value:""
  in
  Printf.printf "opaque    %s (%b)\n"
    (Cosmos_tx.Msg.type_url unknown)
    (Cosmos_tx.Msg.is_approvable unknown);

  (* Rpc: confirmation is tagged, not boolean. *)
  (match Cosmos_rpc.Confirmation.In_mempool with
  | Cosmos_rpc.Confirmation.In_mempool ->
      print_endline "confirm   in mempool is not delivered"
  | _ -> ());

  (* Proto and crypto have no value-level surface to touch until L1/L2 land;
     the dune stanza above is what keeps them in the link. *)
  print_endline "linked    cosmos-proto, cosmos-crypto"
