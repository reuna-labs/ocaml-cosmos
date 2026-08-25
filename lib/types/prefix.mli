(** Bech32 human-readable parts.

    A Cosmos chain spells the same 20 or 32 address bytes under three prefixes
    -- account, validator operator and consensus node -- and they are not
    interchangeable. [cosmos1...] and [cosmosvaloper1...] differ only in the
    prefix, so a library that treated the prefix as formatting would let a
    delegation be built as a transfer without a type error anywhere. *)

type kind = Account | Validator | Consensus

type t
(** A validated human-readable part: the chain's base prefix plus the suffix for
    [kind]. *)

val make : base:string -> kind -> (t, string) result
(** [make ~base kind] is the prefix for [kind] on the chain whose account prefix
    is [base] -- [Validator] appends [valoper], [Consensus] appends [valcons].
    [Error] if [base] is not a legal bech32 human-readable part. *)

val to_string : t -> string
val kind : t -> kind
