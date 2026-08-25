(** Denominations.

    A denomination is the SDK's name for a unit: [uatom], [uosmo], or an IBC
    voucher such as
    [ibc/27394FB092D2ECCD56123C74F36E4C1F926001CEADA9CA97EA622B25F41E5EB2].

    The rule is one regular expression, [^[a-zA-Z][a-zA-Z0-9/:._-]{2,127}$] —
    three to a hundred and twenty eight characters, starting with a letter
    ([types/coin.go:848] at the pinned revision). It is matched here by hand
    rather than with a regular-expression library, which keeps the offline
    closure free of one.

    {2 What a denomination does not tell you}

    Nothing about value. [uatom] and [atom] differ by a factor of a million and
    both are valid; an IBC voucher's denomination identifies a channel path, not
    an asset a human would recognise. Resolving either is the profile's job and,
    for vouchers, the node's. This module only says whether a string is a
    denomination at all. *)

type t

val of_string : string -> (t, string) result
val to_string : t -> string
val equal : t -> t -> bool

val is_ibc_voucher : t -> bool
(** [true] for the [ibc/…] form. Worth asking before showing a denomination to a
    human: the part after the slash is a hash of the channel path, so the name
    carries no indication of what the asset is or which chain it came from. *)
