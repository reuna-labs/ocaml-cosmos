module Sign_doc = Cosmos_tx.Sign_doc
module Chain_id = Cosmos_types.Chain_id

let equal_fields a b =
  String.equal (Sign_doc.body_bytes a) (Sign_doc.body_bytes b)
  && String.equal (Sign_doc.auth_info_bytes a) (Sign_doc.auth_info_bytes b)
  && Chain_id.equal (Sign_doc.chain_id a) (Sign_doc.chain_id b)
  && Int64.equal (Sign_doc.account_number a) (Sign_doc.account_number b)

let () =
  Crowbar.add_test ~name:"SignDoc decode is total" [ Crowbar.bytes ]
    (fun bytes ->
      Crowbar.check (match Sign_doc.of_bytes bytes with _ -> true))

let () =
  Crowbar.add_test ~name:"normalised SignDoc preserves signed fields"
    [ Crowbar.bytes ] (fun bytes ->
      match Sign_doc.of_bytes bytes with
      | Error _ -> ()
      | Ok doc ->
          let normalised = Sign_doc.to_bytes doc in
          let decoded = Result.get_ok (Sign_doc.of_bytes normalised) in
          Crowbar.check (equal_fields doc decoded);
          Crowbar.check_eq ~pp:Crowbar.pp_string normalised
            (Sign_doc.to_bytes decoded))

let () =
  Crowbar.add_test ~name:"SignDoc digest covers its normalised bytes"
    [ Crowbar.bytes ] (fun bytes ->
      match Sign_doc.of_bytes bytes with
      | Error _ -> ()
      | Ok doc ->
          let expected =
            Digestif.SHA256.(
              to_raw_string (digest_string (Sign_doc.to_bytes doc)))
          in
          Crowbar.check_eq ~pp:Crowbar.pp_string expected (Sign_doc.digest doc))
