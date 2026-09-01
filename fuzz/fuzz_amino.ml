module Tx = Cosmos_tx
module Types = Cosmos_types

let address bytes =
  Result.get_ok (Types.Address.of_bytes Types.Prefix.cosmos bytes)

let coin amount =
  Result.get_ok
    (Types.Coin.of_strings ~denom:"uatom" ~amount:(string_of_int amount))

let message =
  Crowbar.choose
    [
      Crowbar.map
        [
          Crowbar.bytes_fixed 20;
          Crowbar.bytes_fixed 20;
          Crowbar.range 1_000_000;
        ]
        (fun from_bytes to_bytes amount ->
          Tx.Msg.Send
            {
              from_address = address from_bytes;
              to_address = address to_bytes;
              amount = [ coin amount ];
            });
      Crowbar.map
        [
          Crowbar.bytes_fixed 20;
          Crowbar.bytes_fixed 20;
          Crowbar.range 1_000_000;
        ]
        (fun from_bytes to_bytes amount ->
          Tx.Msg.Multi_send
            {
              inputs =
                [ { address = address from_bytes; coins = [ coin amount ] } ];
              outputs =
                [ { address = address to_bytes; coins = [ coin amount ] } ];
            });
      Crowbar.map
        [ Crowbar.bytes_fixed 20; Crowbar.range 1_000_000 ]
        (fun sender amount ->
          Tx.Msg.Ibc_transfer
            {
              source_port = "transfer";
              source_channel = "channel-0";
              token = coin amount;
              sender = address sender;
              receiver = "osmo1destination";
              timeout_height = { revision_number = 1L; revision_height = 2L };
              timeout_timestamp = 3L;
              memo = "";
            });
      Crowbar.map
        [
          Crowbar.bytes_fixed 20;
          Crowbar.bytes_fixed 20;
          Crowbar.range 1_000_000;
        ]
        (fun sender contract amount ->
          Tx.Msg.Wasm_execute
            {
              sender = address sender;
              contract = address contract;
              msg = Printf.sprintf {|{"z":%d,"a":1}|} amount;
              funds = [];
            });
    ]

let public_key =
  Result.get_ok
    (Cosmos_crypto.public_key_of_bytes
       (String.init 33 (fun i ->
            if i = 0 then '\x02' else if i = 32 then '\x01' else '\x00')))

let auth_info () =
  Result.get_ok
    (Tx.Auth_info.make
       ~signers:
         [
           {
             public_key = Some (Tx.Auth_info.Secp256k1 public_key);
             mode = Tx.Auth_info.Legacy_amino_json;
             sequence = 7L;
           };
         ]
       ~fee:
         {
           amount = [ coin 1000 ];
           gas_limit = 200_000L;
           payer = None;
           granter = None;
         })

let chain_id = Result.get_ok (Types.Chain_id.of_string "cosmoshub-4")

let () =
  Crowbar.add_test ~name:"generated Amino JSON is deterministic and valid"
    [ Crowbar.list message ]
    (fun messages ->
      Crowbar.guard (messages <> [] && List.length messages <= 8);
      let body = Result.get_ok (Tx.Body.make ~messages ()) in
      let encode () =
        Tx.Amino_json.sign_bytes ~body ~auth_info:(auth_info ()) ~chain_id
          ~account_number:42L
      in
      match (encode (), encode ()) with
      | Ok a, Ok b ->
          Crowbar.check_eq ~pp:Crowbar.pp_string a b;
          Crowbar.check
            (match Yojson.Safe.from_string a with
            | _ -> true
            | exception _ -> false)
      | Error a, Error b -> Crowbar.check_eq ~pp:Crowbar.pp_string a b
      | _ -> Crowbar.fail "the same Amino document changed result")

let () =
  Crowbar.add_test ~name:"inline CosmWasm JSON keys are sorted"
    [ Crowbar.bytes_fixed 20; Crowbar.bytes_fixed 20; Crowbar.range 1_000_000 ]
    (fun sender contract amount ->
      let message =
        Tx.Msg.Wasm_execute
          {
            sender = address sender;
            contract = address contract;
            msg = Printf.sprintf {|{"z":%d,"a":1}|} amount;
            funds = [];
          }
      in
      let body = Result.get_ok (Tx.Body.make ~messages:[ message ] ()) in
      let encoded =
        Result.get_ok
          (Tx.Amino_json.sign_bytes ~body ~auth_info:(auth_info ()) ~chain_id
             ~account_number:42L)
      in
      let expected = Printf.sprintf {|{"a":1,"z":%d}|} amount in
      let rec contains i =
        i + String.length expected <= String.length encoded
        && (String.sub encoded i (String.length expected) = expected
           || contains (i + 1))
      in
      Crowbar.check (contains 0))
