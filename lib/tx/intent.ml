module Address = Cosmos_types.Address
module Amount = Cosmos_types.Amount
module Coin = Cosmos_types.Coin
module Chain_id = Cosmos_types.Chain_id

type transfer = {
  from_address : Address.t;
  to_address : Address.t;
  amount : Coin.t list;
}

type action =
  | Transfer of transfer
  | Multi_transfer of { inputs : Msg.io list; outputs : Msg.io list }
  | Ibc_out of {
      channel : string;
      token : Coin.t;
      sender : Address.t;
      receiver : string;
      timeout_timestamp : int64;
    }
  | Contract_call of {
      sender : Address.t;
      contract : Address.t;
      call : string;
      funds : Coin.t list;
    }
  | Unexplainable of { type_url : string; why : string }

type t = {
  chain_id : Chain_id.t;
  account_number : int64;
  sequence : int64;
  actions : action list;
  fee : Coin.t list;
  gas_limit : int64;
  fee_payer : Address.t option;
  fee_granter : Address.t option;
  memo : string;
  timeout_height : int64;
  timeout_timestamp : int64;
  unordered : bool;
  extension_options : (string * string) list;
  signer_count : int;
}

let ( let* ) = Result.bind

let action_of_msg : Msg.t -> action = function
  | Msg.Send s ->
      Transfer
        {
          from_address = s.from_address;
          to_address = s.to_address;
          amount = s.amount;
        }
  | Msg.Multi_send m ->
      Multi_transfer { inputs = m.inputs; outputs = m.outputs }
  | Msg.Ibc_transfer t ->
      Ibc_out
        {
          channel = t.source_channel;
          token = t.token;
          sender = t.sender;
          receiver = t.receiver;
          timeout_timestamp = t.timeout_timestamp;
        }
  | Msg.Wasm_execute w ->
      Contract_call
        {
          sender = w.sender;
          contract = w.contract;
          call = w.msg;
          funds = w.funds;
        }
  | Msg.Opaque { type_url; why; _ } -> Unexplainable { type_url; why }

let build ~body ~auth_info ~chain_id ~account_number =
  let fee = Auth_info.fee auth_info in
  let signers = Auth_info.signers auth_info in
  let sequence =
    match signers with (s : Auth_info.signer) :: _ -> s.sequence | [] -> 0L
  in
  {
    chain_id;
    account_number;
    sequence;
    actions = List.map action_of_msg (Body.messages body);
    fee = fee.amount;
    gas_limit = fee.gas_limit;
    fee_payer = fee.payer;
    fee_granter = fee.granter;
    memo = Body.memo body;
    timeout_height = Body.timeout_height body;
    timeout_timestamp = Body.timeout_timestamp body;
    unordered = Body.unordered body;
    extension_options =
      Body.extension_options body @ Body.non_critical_extension_options body;
    signer_count = List.length signers;
  }

let of_sign_doc ~base doc =
  (* Decoded from the bytes the signature covers, not from anything a builder
     said. If the two disagree, these are what the chain acts on. *)
  let* body = Body.of_bytes ~base (Sign_doc.body_bytes doc) in
  let* auth_info = Auth_info.of_bytes ~base (Sign_doc.auth_info_bytes doc) in
  Ok
    (build ~body ~auth_info ~chain_id:(Sign_doc.chain_id doc)
       ~account_number:(Sign_doc.account_number doc))

let of_tx ~base tx ~chain_id ~account_number =
  let doc =
    Sign_doc.make ~body:(Tx.body tx) ~auth_info:(Tx.auth_info tx) ~chain_id
      ~account_number
  in
  of_sign_doc ~base doc

let is_fully_explainable t =
  t.extension_options = []
  && List.for_all (function Unexplainable _ -> false | _ -> true) t.actions

let pp_coins ppf l =
  match l with
  | [] -> Format.pp_print_string ppf "nothing"
  | l ->
      Format.pp_print_list
        ~pp_sep:(fun ppf () -> Format.fprintf ppf " + ")
        (fun ppf c -> Format.pp_print_string ppf (Coin.to_string c))
        ppf l

let pp_action ppf = function
  | Transfer t ->
      Format.fprintf ppf "@[<h>send %a@ from %s@ to %s@]" pp_coins t.amount
        (Address.to_bech32 t.from_address)
        (Address.to_bech32 t.to_address)
  | Multi_transfer m ->
      Format.fprintf ppf "@[<v>multi-send@,";
      List.iter
        (fun (i : Msg.io) ->
          Format.fprintf ppf "  from %s: %a@,"
            (Address.to_bech32 i.address)
            pp_coins i.coins)
        m.inputs;
      List.iter
        (fun (o : Msg.io) ->
          Format.fprintf ppf "  to   %s: %a@,"
            (Address.to_bech32 o.address)
            pp_coins o.coins)
        m.outputs;
      Format.fprintf ppf "@]"
  | Ibc_out i ->
      Format.fprintf ppf
        "@[<h>ibc transfer %s@ from %s@ over %s@ to %s (another chain; its \
         prefix is not checkable here)@]"
        (Coin.to_string i.token)
        (Address.to_bech32 i.sender)
        i.channel i.receiver
  | Contract_call c ->
      Format.fprintf ppf
        "@[<v>call contract %s@,\
        \  as    %s@,\
        \  funds %a@,\
        \  call  %s@,\
        \  (the call is shown, not interpreted: there is no trusted source for \
         this contract's schema)@]"
        (Address.to_bech32 c.contract)
        (Address.to_bech32 c.sender)
        pp_coins c.funds c.call
  | Unexplainable u ->
      Format.fprintf ppf "@[<h>UNEXPLAINABLE %s (%s)@]" u.type_url u.why

let pp ppf t =
  Format.fprintf ppf "@[<v>";
  Format.fprintf ppf "chain          %s@," (Chain_id.to_string t.chain_id);
  Format.fprintf ppf "account        %Ld, sequence %Ld@," t.account_number
    t.sequence;
  if t.unordered then
    Format.fprintf ppf "               UNORDERED: no sequence check@,";
  Format.fprintf ppf "signers        %d@," t.signer_count;
  List.iteri
    (fun i a -> Format.fprintf ppf "action %-2d      %a@," (i + 1) pp_action a)
    t.actions;
  Format.fprintf ppf "fee            %a for %Ld gas@," pp_coins t.fee
    t.gas_limit;
  (match t.fee_payer with
  | Some a -> Format.fprintf ppf "fee payer      %s@," (Address.to_bech32 a)
  | None -> ());
  (match t.fee_granter with
  | Some a ->
      Format.fprintf ppf "fee granter    %s (someone else pays)@,"
        (Address.to_bech32 a)
  | None -> ());
  if t.memo <> "" then Format.fprintf ppf "memo           %s@," t.memo;
  if t.timeout_height <> 0L then
    Format.fprintf ppf "valid until    height %Ld@," t.timeout_height;
  if t.timeout_timestamp <> 0L then
    Format.fprintf ppf "valid until    timestamp %Ld@," t.timeout_timestamp;
  List.iter
    (fun (url, _) -> Format.fprintf ppf "EXTENSION      %s@," url)
    t.extension_options;
  Format.fprintf ppf "@]"
