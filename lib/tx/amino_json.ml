module Address = Cosmos_types.Address
module Amount = Cosmos_types.Amount
module Coin = Cosmos_types.Coin
module Denom = Cosmos_types.Denom
module J = Json_out

let ( let* ) = Result.bind

(* From (amino.name) in the pinned .proto files:
     cosmos/bank/v1beta1/tx.proto:41,62
     ibc/applications/transfer/v1/tx.proto:29
     cosmwasm/wasm/v1/tx.proto:190
   Note that MsgTransfer's is cosmos-sdk/MsgTransfer despite living in ibc. *)
let amino_name : Msg.t -> (string, string) result = function
  | Msg.Send _ -> Ok "cosmos-sdk/MsgSend"
  | Msg.Multi_send _ -> Ok "cosmos-sdk/MsgMultiSend"
  | Msg.Ibc_transfer _ -> Ok "cosmos-sdk/MsgTransfer"
  | Msg.Wasm_execute _ -> Ok "wasm/MsgExecuteContract"
  | Msg.Opaque { type_url; _ } ->
      Error
        (Printf.sprintf
           "amino: %s has no amino name, so it cannot be signed in this mode"
           type_url)

(* Integers are decimal strings throughout. *)
let int64 v = J.Str (Int64.to_string v)

let coin c =
  J.Obj
    [
      ("denom", J.Str (Denom.to_string (Coin.denom c)));
      ("amount", J.Str (Amount.to_string (Coin.amount c)));
    ]

let coins l = J.Arr (List.map coin l)
let addr a = J.Str (Address.to_bech32 a)

(* Fields are dropped when empty unless (amino.dont_omitempty) says otherwise.
   The lists below are dont_omitempty, so they are always written even when
   they are []. *)
let opt_string k v = if v = "" then [] else [ (k, J.Str v) ]
let opt_int64 k v = if v = 0L then [] else [ (k, int64 v) ]

let msg_value : Msg.t -> (J.t, string) result = function
  | Msg.Send s ->
      Ok
        (J.Obj
           [
             ("from_address", addr s.from_address);
             ("to_address", addr s.to_address);
             (* dont_omitempty *)
             ("amount", coins s.amount);
           ])
  | Msg.Multi_send m ->
      let io (i : Msg.io) =
        J.Obj [ ("address", addr i.address); ("coins", coins i.coins) ]
      in
      Ok
        (J.Obj
           [
             (* both dont_omitempty *)
             ("inputs", J.Arr (List.map io m.inputs));
             ("outputs", J.Arr (List.map io m.outputs));
           ])
  | Msg.Ibc_transfer t ->
      Ok
        (J.Obj
           ([
              ("source_port", J.Str t.source_port);
              ("source_channel", J.Str t.source_channel);
              (* dont_omitempty *)
              ("token", coin t.token);
              ("sender", addr t.sender);
              ("receiver", J.Str t.receiver);
              (* dont_omitempty; its own fields are ordinary, so a zero
               revision_number drops out of the inner object. *)
              ( "timeout_height",
                J.Obj
                  (opt_int64 "revision_number" t.timeout_height.revision_number
                  @ opt_int64 "revision_height" t.timeout_height.revision_height
                  ) );
            ]
           @ opt_int64 "timeout_timestamp" t.timeout_timestamp
           @ opt_string "memo" t.memo))
  | Msg.Wasm_execute w ->
      (* (amino.encoding) = "inline_json": the bytes are spliced in as JSON, and
       the SDK re-serialises them, which sorts the keys. Parsing and re-emitting
       is therefore not optional -- passing the caller's bytes through would
       sign something the node does not compute. *)
      let* parsed = Json_in.parse w.msg in
      Ok
        (J.Obj
           [
             ("sender", addr w.sender);
             ("contract", addr w.contract);
             ("msg", Json_in.to_json parsed);
             (* dont_omitempty *)
             ("funds", coins w.funds);
           ])
  | Msg.Opaque { type_url; _ } ->
      Error (Printf.sprintf "amino: %s cannot be encoded" type_url)

let msg m =
  let* type_ = amino_name m in
  let* value = msg_value m in
  Ok (J.Obj [ ("type", J.Str type_); ("value", value) ])

let fee (f : Auth_info.fee) =
  J.Obj
    ([ ("amount", coins f.amount); ("gas", int64 f.gas_limit) ]
    @ (match f.payer with Some a -> [ ("payer", addr a) ] | None -> [])
    @ match f.granter with Some a -> [ ("granter", addr a) ] | None -> [])

let sign_bytes ~body ~auth_info ~chain_id ~account_number =
  let signers = Auth_info.signers auth_info in
  match signers with
  | [] -> Error "amino: no signers"
  | _ :: _ :: _ ->
      (* The document carries one sequence. Signing it for the first signer and
       calling that the transaction's amino bytes would be a claim about the
       others that is not true. *)
      Error
        "amino: the document holds one sequence, so a multi-signer transaction \
         cannot be represented in this mode"
  | [ signer ] ->
      let* msgs =
        List.fold_left
          (fun acc m ->
            let* acc = acc in
            let* j = msg m in
            Ok (j :: acc))
          (Ok []) (Body.messages body)
      in
      let msgs = List.rev msgs in
      if
        Body.extension_options body <> []
        || Body.non_critical_extension_options body <> []
      then
        Error
          "amino: extension options have no amino representation, so what \
           would be signed would not describe the transaction"
      else
        let doc =
          J.Obj
            ([
               ("account_number", int64 account_number);
               ("chain_id", J.Str (Cosmos_types.Chain_id.to_string chain_id));
               ("fee", fee (Auth_info.fee auth_info));
               ("memo", J.Str (Body.memo body));
               ("msgs", J.Arr msgs);
               ("sequence", int64 signer.sequence);
             ]
            (* timeout_height is a top-level field of the document as well as a
             body field. Established from the SDK's encoder, not from the
             schema -- see conformance/simd. *)
            @ opt_int64 "timeout_height" (Body.timeout_height body))
        in
        Ok (J.to_string doc)

let digest ~body ~auth_info ~chain_id ~account_number =
  let* bytes = sign_bytes ~body ~auth_info ~chain_id ~account_number in
  Ok Digestif.SHA256.(to_raw_string (digest_string bytes))
