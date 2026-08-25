(** [LegacyDec] — the SDK's fixed-point decimal.

    Eighteen decimal places, always ([math/legacy_dec.go:20-21],
    [LegacyPrecision = 18]). Not a float, and not a rational: it is an integer
    scaled by 10{^ 18}, and it reaches the wire as that scaled integer in
    decimal ASCII, not as the human spelling. ["0.025"] is ["25000000000000000"]
    on the wire and both are the same value, which is why both are constructible
    here and neither is called [of_string] alone.

    {2 What it is used for, and what it is not}

    Gas prices, and nothing else in the launch slice. A minimum gas price is
    quoted per unit of gas, so it is unavoidably fractional: [0.025uatom] is the
    Hub's, and no integer type expresses it.

    It is deliberately not a general numeric type. There is no division, no
    addition of one price to another, no negative values. The one arithmetic
    operation is {!mul_ceil}, because the one thing a signer computes is a fee.

    {2 Why ceiling}

    A fee below the node's minimum is rejected. Rounding a fee down, or to
    nearest, produces a transaction that is refused for being one base unit
    short — so {!mul_ceil} rounds up, and a caller that wants a different policy
    is choosing to pay less than the node asked for. *)

type t

val zero : t

val precision : int
(** 18. *)

val of_decimal_string : string -> (t, string) result
(** The human spelling: ["0.025"], ["1"], ["0.000000000000000001"]. At most
    {!precision} places after the point; more is an error rather than a silent
    truncation, since truncating a price is a fee that comes out wrong. *)

val to_decimal_string : t -> string
(** The human spelling, with trailing zeros removed and a leading ["0"] before
    the point. Round-trips {!of_decimal_string}. *)

val of_scaled_string : string -> (t, string) result
(** The wire spelling: the integer already scaled by 10{^ 18}. *)

val to_scaled_string : t -> string

val mul_ceil : t -> Amount.t -> (Amount.t, string) result
(** [mul_ceil price n] is the smallest integer at least [price * n].

    For a fee: [n] is the gas limit. *)

val is_zero : t -> bool
val compare : t -> t -> int
val equal : t -> t -> bool
