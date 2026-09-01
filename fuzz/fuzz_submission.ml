module Rpc = Cosmos_rpc
module Sub = Rpc.Submission
module Types = Cosmos_types

let chain_id = Result.get_ok (Types.Chain_id.of_string "cosmoshub-4")

let signer =
  Result.get_ok
    (Types.Address.of_bytes Types.Prefix.cosmos (String.make 20 '\x01'))

let config = { Sub.chain_id; signer; max_rebuilds = 3; max_polls = 5 }

let status ?(wrong = false) ?(catching_up = false) () =
  {
    Rpc.Method.chain_id =
      (if wrong then Result.get_ok (Types.Chain_id.of_string "wrong-1")
       else chain_id);
    node_version = "0.38";
    latest_block_height = 10L;
    latest_block_time = "2026-01-01T00:00:00Z";
    catching_up;
  }

let account =
  Rpc.Query.Base
    {
      address = signer;
      account_number = 1L;
      sequence = 2L;
      has_public_key = true;
    }

type event =
  | Status of bool * bool
  | Account
  | Other_account
  | Signed of string
  | Broadcast of int * string
  | Tx of int
  | Not_found
  | Transport_error
  | Malformed_error

let event =
  Crowbar.choose
    [
      Crowbar.map [ Crowbar.bool; Crowbar.bool ] (fun wrong catching ->
          Status (wrong, catching));
      Crowbar.const Account;
      Crowbar.const Other_account;
      Crowbar.map [ Crowbar.bytes ] (fun bytes -> Signed bytes);
      Crowbar.map
        [ Crowbar.range 40; Crowbar.bytes ]
        (fun code hash -> Broadcast (code, hash));
      Crowbar.map [ Crowbar.range 40 ] (fun code -> Tx code);
      Crowbar.const Not_found;
      Crowbar.const Transport_error;
      Crowbar.const Malformed_error;
    ]

let apply state = function
  | Status (wrong, catching_up) ->
      Sub.on_status state (status ~wrong ~catching_up ())
  | Account -> Sub.on_account state account
  | Other_account ->
      Sub.on_account state (Rpc.Query.Other { type_url = "/module.Account" })
  | Signed bytes -> Sub.on_signed state bytes
  | Broadcast (code, hash) ->
      Sub.on_broadcast state
        { Rpc.Method.code; codespace = "sdk"; log = ""; hash }
  | Tx code ->
      Sub.on_tx state
        (Ok
           {
             Rpc.Method.hash = "hash";
             height = 10L;
             code;
             codespace = "sdk";
             log = "";
             gas_wanted = 2L;
             gas_used = 1L;
           })
  | Not_found ->
      Sub.on_tx state
        (Error (Rpc.Error.Rpc { code = -32603; message = "not found" }))
  | Transport_error -> Sub.on_error state (Rpc.Error.Transport "injected")
  | Malformed_error -> Sub.on_error state (Rpc.Error.Malformed "injected")

let equal_outcome a b = a = b

let () =
  Crowbar.add_test ~name:"arbitrary event order is total and completion absorbs"
    [ Crowbar.list event ]
    (fun events ->
      let rec drive state = function
        | [] -> ()
        | event :: rest ->
            let before = Sub.finished state in
            let state' = apply state event in
            (match before with
            | None -> ()
            | Some outcome ->
                Crowbar.check
                  (match Sub.finished state' with
                  | Some outcome' -> equal_outcome outcome outcome'
                  | None -> false));
            ignore (Sub.next state');
            drive state' rest
      in
      drive (Sub.start config) events)

let () =
  Crowbar.add_test ~name:"only caller-supplied signed bytes are broadcast"
    [ Crowbar.list event ]
    (fun events ->
      let rec drive state supplied = function
        | [] -> ()
        | event :: rest ->
            let state, supplied =
              match event with
              | Signed bytes -> (apply state event, bytes :: supplied)
              | _ -> (apply state event, supplied)
            in
            (match Sub.next state with
            | Sub.Broadcast bytes ->
                Crowbar.check (List.exists (String.equal bytes) supplied)
            | _ -> ());
            drive state supplied rest
      in
      drive (Sub.start config) [] events)
