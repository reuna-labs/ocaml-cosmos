(** Bech32 human-readable parts.

    A Cosmos chain spells the same address bytes under three prefixes — account,
    validator operator and consensus node — and they are not interchangeable.
    [cosmos1…] and [cosmosvaloper1…] differ only in the prefix, so a library
    that treated the prefix as formatting would let a delegation be built as a
    transfer without a type error anywhere. That is why the prefix is part of
    the address type and not part of printing it.

    The suffixes are the SDK's: [valoper] for a validator operator, [valcons]
    for a consensus node, nothing for an account. See [types/address.go:66-76]
    at the pinned revision, cited in [docs/protocol-pin.md]. *)

type kind =
  | Account  (** [cosmos1…] — what holds a balance and signs *)
  | Validator  (** [cosmosvaloper1…] — a validator's operator address *)
  | Consensus  (** [cosmosvalcons1…] — a consensus node address *)

type t

val make : base:string -> kind -> (t, string) result
(** [make ~base kind] is the prefix for [kind] on the chain whose account prefix
    is [base].

    [base] must be 1..77 lower-case letters and digits. The SDK does not require
    that — bech32 permits any printable ASCII in a human-readable part — but
    every deployed chain prefix is of this form, and accepting more would mean
    accepting a prefix that renders differently from how it was written. The cap
    is 77 rather than bech32's 83 so that [base ^ "valoper"] still fits.

    [Error] if [base] is malformed, or if it already ends in [valoper] or
    [valcons], which would make the result ambiguous with another chain's
    account prefix. *)

val of_hrp : base:string -> string -> (t, string) result
(** [of_hrp ~base hrp] recognises [hrp] as one of the three prefixes belonging
    to [base], and tells you which.

    It takes [base] rather than inferring it because inference is genuinely
    ambiguous: [cosmosvaloper] is the validator prefix of [cosmos] and would
    equally be the account prefix of a chain called [cosmosvaloper]. A caller
    always knows which chain it is talking to — it is in the profile and in the
    chain id — so requiring it costs nothing and removes the guess. *)

val to_string : t -> string
(** The human-readable part itself, e.g. ["cosmosvaloper"]. *)

val base : t -> string
(** The chain's account prefix, e.g. ["cosmos"], whichever [kind] this is. *)

val kind : t -> kind
val equal : t -> t -> bool

val cosmos : t
(** [cosmos], the SDK's default account prefix ([types/address.go:39] at the
    pinned revision). Present because it is what every example and every test
    vector uses, not because it is a default anything here should reach for. *)
