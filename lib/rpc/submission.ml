module Address = Cosmos_types.Address
module Chain_id = Cosmos_types.Chain_id

type config = {
  chain_id : Chain_id.t;
  signer : Address.t;
  max_rebuilds : int;
  max_polls : int;
}

type request =
  | Check_node
  | Fetch_account
  | Build_and_sign of { account_number : int64; sequence : int64 }
  | Broadcast of string
  | Poll of { hash : string }

type outcome =
  | Delivered of { hash : string; height : int64; gas_used : int64 }
  | Rejected of {
      stage : [ `Check | `Deliver ];
      code : int;
      codespace : string;
      log : string;
    }
  | Gave_up of string

type state =
  | Checking_node
  | Fetching_account
  | Awaiting_signature of { account_number : int64; sequence : int64 }
  | Broadcasting of string
  | Polling of { hash : string; polls : int }
  | Done of outcome

type t = { config : config; state : state; rebuilds : int }

let start config = { config; state = Checking_node; rebuilds = 0 }

let next t =
  match t.state with
  | Checking_node -> Check_node
  | Fetching_account -> Fetch_account
  | Awaiting_signature { account_number; sequence } ->
      Build_and_sign { account_number; sequence }
  | Broadcasting bytes -> Broadcast bytes
  | Polling { hash; _ } -> Poll { hash }
  | Done _ ->
      (* Nothing left to do; callers check [finished] first. *) Check_node

let finished t = match t.state with Done o -> Some o | _ -> None

let sequence_consumed t =
  match t.state with
  | Done (Rejected { stage = `Check; _ }) -> Some false
  | Done (Rejected { stage = `Deliver; _ }) -> Some true
  | Done (Delivered _) -> Some true
  | _ -> None

let give_up t reason = { t with state = Done (Gave_up reason) }

(* Going back for a fresh sequence. Never an increment: whether the last
   attempt consumed one is exactly what is not known here. *)
let rebuild t reason =
  if t.rebuilds >= t.config.max_rebuilds then
    give_up t
      (Printf.sprintf "gave up after %d rebuilds; last reason: %s" t.rebuilds
         reason)
  else { t with state = Fetching_account; rebuilds = t.rebuilds + 1 }

let on_status t (s : Method.status) =
  match t.state with
  | Checking_node ->
      if not (Chain_id.equal s.chain_id t.config.chain_id) then
        (* Before anything is signed. A transaction built for the wrong chain is
         the one mistake with no remedy afterwards. *)
        give_up t
          (Printf.sprintf "node serves %s, expected %s"
             (Chain_id.to_string s.chain_id)
             (Chain_id.to_string t.config.chain_id))
      else if s.catching_up then
        give_up t
          "node is catching up, so its account state is behind the chain"
      else { t with state = Fetching_account }
  | _ -> t

let on_account t (a : Query.account_result) =
  match (t.state, a) with
  | Fetching_account, Query.Base acct ->
      if not (Address.equal acct.address t.config.signer) then
        give_up t "the account query answered about a different address"
      else
        {
          t with
          state =
            Awaiting_signature
              { account_number = acct.account_number; sequence = acct.sequence };
        }
  | Fetching_account, Query.Other { type_url } ->
      give_up t
        (Printf.sprintf "the signer's account is a %s, which cannot sign"
           type_url)
  | _ -> t

let on_signed t bytes =
  match t.state with
  | Awaiting_signature _ -> { t with state = Broadcasting bytes }
  | _ -> t

let on_broadcast t (r : Method.broadcast_result) =
  match t.state with
  | Broadcasting _ ->
      if r.code = 0 then { t with state = Polling { hash = r.hash; polls = 0 } }
      else if
        (* CheckTx said no. The sequence was not consumed -- but this machine
         still goes back and asks rather than reusing the one it had, because
         "not consumed" is a fact about this attempt and not about what else
         may have happened to the account meanwhile.

         Code 32 is the SDK's sequence mismatch, and it is the one worth
         rebuilding for: something else moved the account on. *)
        r.code = 32
      then rebuild t "sequence mismatch"
      else
        {
          t with
          state =
            Done
              (Rejected
                 {
                   stage = `Check;
                   code = r.code;
                   codespace = r.codespace;
                   log = r.log;
                 });
        }
  | _ -> t

let on_tx t result =
  match (t.state, result) with
  | Polling { hash; polls }, Error e ->
      (* Not found yet is reported in the envelope, so it looks like an error and
       is not one. Anything else is. *)
      if Error.is_retryable e || match e with Error.Rpc _ -> true | _ -> false
      then
        if polls >= t.config.max_polls then
          give_up t
            (Printf.sprintf
               "transaction was accepted into a mempool but had not landed \
                after %d polls; its fate is unknown"
               polls)
        else { t with state = Polling { hash; polls = polls + 1 } }
      else give_up t (Error.to_string e)
  | Polling _, Ok (r : Method.tx_result) ->
      if r.code = 0 then
        {
          t with
          state =
            Done
              (Delivered
                 { hash = r.hash; height = r.height; gas_used = r.gas_used });
        }
      else
        (* It landed in a block and failed. The sequence was consumed and the fee
         was taken, which is why this is not a rebuild. *)
        {
          t with
          state =
            Done
              (Rejected
                 {
                   stage = `Deliver;
                   code = r.code;
                   codespace = r.codespace;
                   log = r.log;
                 });
        }
  | _ -> t

let on_error t e =
  if not (Error.is_retryable e) then give_up t (Error.to_string e)
  else
    match t.state with
    | Checking_node | Fetching_account -> t (* ask again *)
    | Awaiting_signature _ -> t
    | Broadcasting _ ->
        (* The dangerous one. A transport failure during broadcast leaves it
         unknown whether the node received the transaction, so re-broadcasting
         the same bytes could double-submit -- except that it cannot, because
         the same sequence can only be used once. Going back for the account
         state is what distinguishes "it never arrived" from "it arrived and
         the connection dropped": if it arrived, the sequence has moved. *)
        rebuild t "the connection dropped during broadcast"
    | Polling { hash; polls } ->
        if polls >= t.config.max_polls then
          give_up t "polling failed repeatedly"
        else { t with state = Polling { hash; polls = polls + 1 } }
    | Done _ -> t
