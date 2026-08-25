module Address = Cosmos_types.Address
module Amount = Cosmos_types.Amount
module Chain_id = Cosmos_types.Chain_id
module Coin = Cosmos_types.Coin
module Denom = Cosmos_types.Denom

type t = {
  chains : Chain_id.t list;
  destinations : Address.t list;
  denoms : Denom.t list;
  max_per_denom : (string * Amount.t) list;
  max_fee : (Amount.t * Denom.t) option;
  max_gas : int64 option;
  memo : bool;
  fee_delegation : bool;
  multiple_actions : bool;
}

let strict =
  {
    chains = [];
    destinations = [];
    denoms = [];
    max_per_denom = [];
    max_fee = None;
    max_gas = None;
    memo = false;
    fee_delegation = false;
    multiple_actions = false;
  }

let allow_chain c t = { t with chains = c :: t.chains }
let allow_transfer_to a t = { t with destinations = a :: t.destinations }
let allow_denom d t = { t with denoms = d :: t.denoms }

let max_amount_per_denom d a t =
  { t with max_per_denom = (Denom.to_string d, a) :: t.max_per_denom }

let max_fee a d t = { t with max_fee = Some (a, d) }
let max_gas g t = { t with max_gas = Some g }
let allow_memo t = { t with memo = true }
let allow_fee_delegation t = { t with fee_delegation = true }
let allow_multiple_actions t = { t with multiple_actions = true }

type verdict = Approved | Refused of string list

let denom_allowed t d = List.exists (Denom.equal d) t.denoms
let destination_allowed t a = List.exists (Address.equal a) t.destinations

let check_coin t ~what c refuse =
  let d = Coin.denom c in
  if not (denom_allowed t d) then
    refuse
      (Printf.sprintf "%s: denomination %s is not permitted" what
         (Denom.to_string d))
  else
    match List.assoc_opt (Denom.to_string d) t.max_per_denom with
    | None -> ()
    | Some limit ->
        if Amount.compare (Coin.amount c) limit > 0 then
          refuse
            (Printf.sprintf "%s: %s exceeds the limit of %s%s" what
               (Coin.to_string c) (Amount.to_string limit) (Denom.to_string d))

let review t (i : Intent.t) =
  let reasons = ref [] in
  let refuse r = reasons := r :: !reasons in

  if not (List.exists (Chain_id.equal i.chain_id) t.chains) then
    refuse
      (Printf.sprintf "chain %s is not permitted"
         (Chain_id.to_string i.chain_id));

  (match i.actions with
  | [] -> refuse "the transaction does nothing"
  | [ _ ] -> ()
  | _ :: _ :: _ when not t.multiple_actions ->
      refuse
        (Printf.sprintf "%d actions, and batching is not permitted"
           (List.length i.actions))
  | _ -> ());

  List.iter
    (fun (a : Intent.action) ->
      match a with
      | Intent.Transfer tr ->
          if not (destination_allowed t tr.to_address) then
            refuse
              (Printf.sprintf "transfer to %s is not permitted"
                 (Address.to_bech32 tr.to_address));
          List.iter (fun c -> check_coin t ~what:"transfer" c refuse) tr.amount
      | Intent.Multi_transfer _ ->
          (* Deliberately never approved. A multi-send's outputs are a set of
           destinations and amounts that would each need checking, and the
           launch policy surface does not describe batches. *)
          refuse "multi-send is not describable by this policy"
      | Intent.Ibc_out o ->
          refuse
            (Printf.sprintf
               "ibc transfer over %s to %s: the destination is on another \
                chain and this policy cannot check it"
               o.channel o.receiver)
      | Intent.Contract_call c ->
          refuse
            (Printf.sprintf
               "contract call to %s: the call is opaque and this policy cannot \
                check what it does"
               (Address.to_bech32 c.contract))
      | Intent.Unexplainable u ->
          refuse (Printf.sprintf "%s cannot be explained (%s)" u.type_url u.why))
    i.actions;

  List.iter (fun c -> check_coin t ~what:"fee" c refuse) i.fee;
  (match t.max_fee with
  | None ->
      refuse "no fee limit is set, and a fee is the easiest amount to inflate"
  | Some (limit, denom) ->
      List.iter
        (fun c ->
          if not (Denom.equal (Coin.denom c) denom) then
            refuse
              (Printf.sprintf "fee is in %s, but the limit is set in %s"
                 (Denom.to_string (Coin.denom c))
                 (Denom.to_string denom))
          else if Amount.compare (Coin.amount c) limit > 0 then
            refuse
              (Printf.sprintf "fee %s exceeds the limit of %s%s"
                 (Coin.to_string c) (Amount.to_string limit)
                 (Denom.to_string denom)))
        i.fee);

  (match t.max_gas with
  | Some g when i.gas_limit > g ->
      refuse (Printf.sprintf "gas limit %Ld exceeds %Ld" i.gas_limit g)
  | _ -> ());

  if i.memo <> "" && not t.memo then
    refuse "a memo is present and memos are not permitted";
  if i.fee_granter <> None && not t.fee_delegation then
    refuse "a fee granter is named and delegation is not permitted";
  if i.fee_payer <> None && not t.fee_delegation then
    refuse "a fee payer is named and delegation is not permitted";
  if i.extension_options <> [] then
    refuse
      (Printf.sprintf
         "%d extension option(s), which can change what the transaction means"
         (List.length i.extension_options));
  if i.signer_count <> 1 then
    refuse
      (Printf.sprintf "%d signers; only single-signer is supported"
         i.signer_count);
  if i.unordered && i.timeout_timestamp = 0L then
    refuse "unordered with no timeout: nothing bounds replay";

  match List.rev !reasons with [] -> Approved | rs -> Refused rs

let pp_verdict ppf = function
  | Approved -> Format.pp_print_string ppf "approved"
  | Refused rs ->
      Format.fprintf ppf "@[<v>refused:@,";
      List.iter (fun r -> Format.fprintf ppf "  - %s@," r) rs;
      Format.fprintf ppf "@]"
