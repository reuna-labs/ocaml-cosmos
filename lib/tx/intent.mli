(** What a transaction means, derived from the bytes about to be signed.

    {2 Derived, not described}

    An intent is built by decoding [body_bytes] and [auth_info_bytes] — the same
    strings the signature will cover — and never from whatever the caller said
    it was building. That is the difference between a display and a review: a
    display shows the caller's inputs, and a review shows what is actually going
    to be signed.

    {!of_sign_doc} therefore takes a {!Sign_doc.t}, and decodes it. If the
    builder and the bytes disagree, the bytes win, because the bytes are what
    the chain will act on.

    {2 Everything that moves value or authority is a field}

    Not a footnote in a rendered string. Fee, gas, granter, payer, sequence,
    account number, chain id, timeout and every message are separate, so a
    policy can test them and a human can be shown them. "Hash approved" is not a
    review, and neither is a paragraph of prose with a number in it. *)

module Address = Cosmos_types.Address
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
      (** Present rather than fatal: a transaction carrying one message this
          library cannot read must still be reviewable for the others, and the
          reviewer must be able to see that one of them is unreadable. *)

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

val of_sign_doc : base:string -> Sign_doc.t -> (t, string) result
(** Decodes the bytes that are about to be signed. *)

val of_tx :
  base:string ->
  Tx.t ->
  chain_id:Chain_id.t ->
  account_number:int64 ->
  (t, string) result
(** The same, for a transaction that already exists — one this signer did not
    build, or one it is about to broadcast. *)

val is_fully_explainable : t -> bool
(** No {!Unexplainable} action, and no extension options. *)

val pp : Format.formatter -> t -> unit
(** A rendering for a human. Every field appears; nothing is summarised away.
    This is for logs and for a reviewer, not for a policy — a policy reads the
    fields. *)
