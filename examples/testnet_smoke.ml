(* The guarded live signing smoke.
   
   This is the only program in the repository that signs with a real key and
   broadcasts. Everything about it is arranged so that running it is a
   deliberate act:
   
   - every input comes from an environment variable and none has a default, so
     there is no way to run it accidentally and no testnet it "just works"
     against;
   - it refuses a chain id it recognises as a mainnet, because the guard that
     matters is the one against the mistake, not the one against the typo;
   - it prints the transcript before broadcasting, so a person watching sees
     what is about to happen rather than what happened.
   
   The key is read from the environment because that is the least bad option
   for a smoke test. It is not how the product signs -- the product's key lives
   in an enclave and never leaves it -- and this program exists to exercise the
   client, not to demonstrate key handling.
   
   usage:
     COSMOS_RPC=https://rpc.provider-sentry-01.hub-testnet.polypore.xyz \
     COSMOS_CHAIN_ID=provider \
     COSMOS_PREFIX=cosmos \
     COSMOS_DENOM=uatom \
     COSMOS_KEY_HEX=<32 bytes of hex, a disposable testnet key> \
     COSMOS_TO=<destination> \
     COSMOS_AMOUNT=1 \
     dune exec examples/testnet_smoke.exe
   
   Add COSMOS_BROADCAST=yes to actually send it. Without that it stops after
   the transcript, which is the useful default: the interesting part is what
   would be signed. *)

let ( let* ) = Lwt.bind

let env name =
  match Sys.getenv_opt name with
  | Some v when String.trim v <> "" -> Ok (String.trim v)
  | _ ->
      Error
        (Printf.sprintf
           "%s is not set. This program has no defaults on purpose; see the \
            comment at the top of examples/testnet_smoke.ml."
           name)

(* Chain ids of networks where a mistake costs real money. Not a security
   boundary -- an operator can name a mainnet anything -- but it catches the
   error this program is most likely to make. *)
let known_mainnets =
  [
    "cosmoshub-4";
    "osmosis-1";
    "celestia";
    "injective-1";
    "neutron-1";
    "noble-1";
    "dydx-mainnet-1";
    "phoenix-1";
    "stride-1";
    "juno-1";
  ]

let unhex h =
  let n = String.length h in
  if n mod 2 <> 0 then Error "not an even number of hex digits"
  else
    try
      Ok
        (String.init (n / 2) (fun i ->
             Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2))))
    with _ -> Error "not hex"

let die msg =
  prerr_endline msg;
  exit 2

let ( let& ) r f = match r with Ok v -> f v | Error e -> die e

let main () =
  let& endpoint = env "COSMOS_RPC" in
  let& chain_id_s = env "COSMOS_CHAIN_ID" in
  let& base = env "COSMOS_PREFIX" in
  let& denom_s = env "COSMOS_DENOM" in
  let& key_hex = env "COSMOS_KEY_HEX" in
  let& to_s = env "COSMOS_TO" in
  let& amount_s = env "COSMOS_AMOUNT" in

  if List.mem chain_id_s known_mainnets then
    die
      (Printf.sprintf
         "%s is a mainnet. This program signs and broadcasts; point it at a \
          testnet."
         chain_id_s);

  let& chain_id = Cosmos_types.Chain_id.of_string chain_id_s in
  let& denom = Cosmos_types.Denom.of_string denom_s in
  let& key_bytes = unhex key_hex in
  let& key = Cosmos_crypto.private_key_of_bytes key_bytes in
  let& recipient = Cosmos_types.Address.of_bech32 ~base to_s in
  let& coin = Cosmos_types.Coin.of_strings ~denom:denom_s ~amount:amount_s in

  let pk = Cosmos_crypto.public_key_of_private key in
  let& prefix = Cosmos_types.Prefix.make ~base Cosmos_types.Prefix.Account in
  let& me =
    Cosmos_types.Address.of_bytes prefix (Cosmos_crypto.address_bytes pk)
  in
  Printf.printf "signer   %s\n" (Cosmos_types.Address.to_bech32 me);
  Printf.printf "chain    %s at %s\n\n" chain_id_s endpoint;

  let* client = Cosmos_rpc_unix.connect_uri endpoint in
  let& client =
    match client with
    | Ok c -> Ok c
    | Error e -> Error (Cosmos_rpc.Error.to_string e)
  in

  (* The submission state machine drives this, so the smoke exercises the same
     sequence discipline the product uses rather than a shortcut. *)
  let config =
    {
      Cosmos_rpc.Submission.chain_id;
      signer = me;
      max_rebuilds = 3;
      max_polls = 20;
    }
  in
  let rec run machine =
    match Cosmos_rpc.Submission.finished machine with
    | Some outcome -> Lwt.return outcome
    | None -> (
        match Cosmos_rpc.Submission.next machine with
        | Cosmos_rpc.Submission.Check_node ->
            let* r = Cosmos_rpc_unix.request client Cosmos_rpc.Method.status in
            run
              (match r with
              | Ok s -> Cosmos_rpc.Submission.on_status machine s
              | Error e -> Cosmos_rpc.Submission.on_error machine e)
        | Cosmos_rpc.Submission.Fetch_account ->
            let* r =
              Cosmos_rpc_unix.request client (Cosmos_rpc.Query.account ~base me)
            in
            run
              (match r with
              | Ok a -> Cosmos_rpc.Submission.on_account machine a
              | Error e -> Cosmos_rpc.Submission.on_error machine e)
        | Cosmos_rpc.Submission.Build_and_sign { account_number; sequence } -> (
            (* Build, review under a policy, and print the transcript before
           anything is broadcast. *)
            let body =
              Result.get_ok
                (Cosmos_tx.Body.make
                   ~messages:
                     [
                       Cosmos_tx.Msg.Send
                         {
                           from_address = me;
                           to_address = recipient;
                           amount = [ coin ];
                         };
                     ]
                   ())
            in
            let fee =
              Cosmos_types.Coin.make ~denom
                ~amount:(Cosmos_types.Coin.amount coin)
            in
            ignore fee;
            let auth_info =
              Result.get_ok
                (Cosmos_tx.Auth_info.make
                   ~signers:
                     [
                       {
                         public_key = Some (Cosmos_tx.Auth_info.Secp256k1 pk);
                         mode = Cosmos_tx.Auth_info.Direct;
                         sequence;
                       };
                     ]
                   ~fee:
                     {
                       amount =
                         [
                           Result.get_ok
                             (Cosmos_types.Coin.of_strings ~denom:denom_s
                                ~amount:"2000");
                         ];
                       gas_limit = 200_000L;
                       payer = None;
                       granter = None;
                     })
            in
            let doc =
              Cosmos_tx.Sign_doc.make ~body ~auth_info ~chain_id ~account_number
            in
            let policy =
              Cosmos_tx.Policy.strict
              |> Cosmos_tx.Policy.allow_chain chain_id
              |> Cosmos_tx.Policy.allow_transfer_to recipient
              |> Cosmos_tx.Policy.allow_denom denom
              |> Cosmos_tx.Policy.max_fee
                   (Result.get_ok (Cosmos_types.Amount.of_string "5000"))
                   denom
            in
            let request =
              Result.get_ok
                (Cosmos_signer.Transcript.request ~chain_id ~account_number
                   ~sequence ~sign_mode:Cosmos_signer.Transcript.Direct
                   ~payload:(Cosmos_tx.Sign_doc.to_bytes doc)
                   ~nonce:
                     (Cosmos_crypto.address_bytes pk ^ Int64.to_string sequence)
                   ~not_after:4_000_000_000L)
            in
            match Cosmos_signer.Transcript.review ~base ~policy request with
            | Error reasons ->
                List.iter (fun r -> prerr_endline ("refused  " ^ r)) reasons;
                exit 1
            | Ok review -> (
                match
                  Cosmos_signer.Transcript.sign review ~key
                    ~measurement:"testnet-smoke"
                with
                | Error e -> die e
                | Ok approval ->
                    print_endline
                      (Format.asprintf "%a" Cosmos_signer.Transcript.pp approval);
                    if Sys.getenv_opt "COSMOS_BROADCAST" <> Some "yes" then (
                      print_endline
                        "\n\
                         COSMOS_BROADCAST is not set to yes, so nothing was \
                         sent.";
                      exit 0);
                    let tx =
                      Result.get_ok
                        (Cosmos_tx.Tx.sign ~body ~auth_info ~chain_id
                           ~account_number ~key)
                    in
                    run
                      (Cosmos_rpc.Submission.on_signed machine
                         (Cosmos_tx.Tx.to_bytes tx))))
        | Cosmos_rpc.Submission.Broadcast bytes ->
            let* r =
              Cosmos_rpc_unix.request client
                (Cosmos_rpc.Method.broadcast_tx_sync bytes)
            in
            run
              (match r with
              | Ok b ->
                  Printf.printf "\nbroadcast code %d hash %s\n%!" b.code b.hash;
                  Cosmos_rpc.Submission.on_broadcast machine b
              | Error e -> Cosmos_rpc.Submission.on_error machine e)
        | Cosmos_rpc.Submission.Poll { hash } ->
            let* r =
              Cosmos_rpc_unix.request client
                (Cosmos_rpc.Method.tx ~hash:(Result.get_ok (unhex hash)))
            in
            print_string ".";
            flush stdout;
            let* () = Lwt_unix.sleep 2.0 in
            run (Cosmos_rpc.Submission.on_tx machine r))
  in
  let* outcome = run (Cosmos_rpc.Submission.start config) in
  print_newline ();
  (match outcome with
  | Cosmos_rpc.Submission.Delivered d ->
      Printf.printf "delivered at height %Ld, gas used %Ld\n" d.height
        d.gas_used
  | Cosmos_rpc.Submission.Rejected r ->
      Printf.printf "rejected at %s: %s code %d: %s\n"
        (match r.stage with
        | `Check -> "CheckTx (the sequence was not consumed)"
        | `Deliver -> "delivery (the sequence WAS consumed)")
        r.codespace r.code r.log
  | Cosmos_rpc.Submission.Gave_up reason -> Printf.printf "gave up: %s\n" reason);
  let* () = Cosmos_rpc_unix.close client in
  Lwt.return
    (match outcome with Cosmos_rpc.Submission.Delivered _ -> 0 | _ -> 1)

let () = exit (Lwt_main.run (main ()))
