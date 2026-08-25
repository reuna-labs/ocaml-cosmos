(** Deciding whether an {!Intent.t} may be signed.

    {2 Fail closed}

    A policy is a list of things that are permitted. Anything not covered is
    refused, and every refusal names what it refused and why — a policy that
    said only "no" would be untestable and unarguable.

    The default {!strict} permits nothing at all. That is the honest starting
    point: a caller has to say what its product does before this can approve it,
    and the alternative — starting permissive and narrowing — means every
    forgotten case is an approval.

    {2 What a policy cannot do}

    Decide whether the signer is authorised. That is the enclave's business, and
    it is a different question from whether this transaction is one the product
    makes. It also cannot verify chain state: whether the destination is who the
    caller thinks, whether the contract does what its name suggests, whether an
    IBC channel goes where it claims. Nothing here has a trusted source for any
    of that. *)

module Address = Cosmos_types.Address
module Amount = Cosmos_types.Amount
module Chain_id = Cosmos_types.Chain_id
module Denom = Cosmos_types.Denom

type t

val strict : t
(** Permits nothing. Every field must be opened deliberately. *)

val allow_chain : Chain_id.t -> t -> t
(** Without at least one, every transaction is refused: an intent whose chain id
    was never named could have come from anywhere. *)

val allow_transfer_to : Address.t -> t -> t
(** A destination for a plain transfer. Repeatable. *)

val allow_denom : Denom.t -> t -> t
(** A denomination that may move, in a transfer or as a fee. Repeatable. *)

val max_amount_per_denom : Denom.t -> Amount.t -> t -> t
(** A ceiling on a single transfer of one denomination. *)

val max_fee : Amount.t -> Denom.t -> t -> t
(** A ceiling on the fee. Worth setting even when the destination is
    constrained: the fee is the one amount an attacker can inflate without
    changing where anything goes. *)

val max_gas : int64 -> t -> t

val allow_memo : t -> t
(** Off by default. A memo is a channel out of the enclave, and an exchange
    deposit that needs one is a deliberate decision rather than an incidental
    convenience. *)

val allow_fee_delegation : t -> t
(** Off by default: a granter means someone other than the signer pays. *)

val allow_multiple_actions : t -> t
(** Off by default. One transaction, one thing — a batch is harder to review and
    a policy that permits batches permits combinations nobody enumerated. *)

type verdict = Approved | Refused of string list

val review : t -> Intent.t -> verdict
(** Every reason, not the first: a caller fixing a policy wants the whole list,
    and a reviewer reading a refusal wants to know everything that was wrong. *)

val pp_verdict : Format.formatter -> verdict -> unit
