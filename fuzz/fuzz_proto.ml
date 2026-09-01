module Tx = Cosmos_tx

let () =
  Crowbar.add_test ~name:"TxRaw decode never raises" [ Crowbar.bytes ]
    (fun bytes ->
      Crowbar.check (match Tx.Tx.of_bytes ~base:"cosmos" bytes with _ -> true))

let () =
  Crowbar.add_test ~name:"TxBody decode never raises" [ Crowbar.bytes ]
    (fun bytes ->
      Crowbar.check
        (match Tx.Body.of_bytes ~base:"cosmos" bytes with _ -> true))

let () =
  Crowbar.add_test ~name:"SignDoc decode never raises" [ Crowbar.bytes ]
    (fun bytes ->
      Crowbar.check (match Tx.Sign_doc.of_bytes bytes with _ -> true))

let () =
  Crowbar.add_test ~name:"decoded transaction retains its wire bytes"
    [ Crowbar.bytes ] (fun bytes ->
      match Tx.Tx.of_bytes ~base:"cosmos" bytes with
      | Error _ -> ()
      | Ok tx ->
          Crowbar.check_eq ~pp:Crowbar.pp_string bytes (Tx.Tx.to_bytes tx))

let () =
  Crowbar.add_test ~name:"decoded body retains its signed bytes"
    [ Crowbar.bytes ] (fun bytes ->
      match Tx.Body.of_bytes ~base:"cosmos" bytes with
      | Error _ -> ()
      | Ok body ->
          Crowbar.check_eq ~pp:Crowbar.pp_string bytes (Tx.Body.to_bytes body))

let () =
  Crowbar.add_test ~name:"an opaque Any makes its body unapprovable"
    [ Crowbar.bytes ] (fun bytes ->
      match Tx.Body.of_bytes ~base:"cosmos" bytes with
      | Error _ -> ()
      | Ok body ->
          let has_opaque =
            List.exists
              (fun message -> not (Tx.Msg.is_approvable message))
              (Tx.Body.messages body)
          in
          Crowbar.check ((not has_opaque) || not (Tx.Body.is_approvable body)))
