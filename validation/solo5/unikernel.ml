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

  (* Tx: a SignDoc over bytes that were never re-encoded, and a message that is
     outside the allow-list and therefore unapprovable. *)
  let _sign_doc =
    Cosmos_tx.Sign_doc.make ~body_bytes:"" ~auth_info_bytes:""
      ~chain_id:"cosmoshub-4" ~account_number:0L
  in
  let unknown =
    Cosmos_tx.Msg.Unknown
      { type_url = "/an.app.chain.v1.MsgWhoKnows"; value = "" }
  in
  (match unknown with
  | Cosmos_tx.Msg.Unknown { type_url; _ } ->
      print_endline ("unapprovable " ^ type_url)
  | _ -> ());

  (* Rpc: confirmation is tagged, not boolean. *)
  (match Cosmos_rpc.Confirmation.In_mempool with
  | Cosmos_rpc.Confirmation.In_mempool ->
      print_endline "confirm   in mempool is not delivered"
  | _ -> ());

  (* Proto and crypto have no value-level surface to touch until L1/L2 land;
     the dune stanza above is what keeps them in the link. *)
  print_endline "linked    cosmos-proto, cosmos-crypto"
