(** Coin amounts: unsigned integers of at most 256 bits.

    {2 Why this exists rather than a dependency}

    A Cosmos amount is [cosmossdk.io/math.Int], which is capped at 256 bits
    ([math/int.go:16], [MaxBitLen = 256]) and reaches the wire as decimal ASCII
    — [Int.Marshal] is [big.Int.MarshalText] ([math/int.go:466]). Sixty-four
    bits is not enough: a token with eighteen decimal places puts a billion
    units at 10{^ 27}, which is past 2{^ 64}.

    The obvious answer is zarith, and it is the wrong one here. This closure
    carries no bignum on purpose — see the note in [dune-project] — so that a
    unikernel needs no GMP. A fixed 256-bit width is not a compromise in this
    setting: it is exactly the range the protocol defines, and a value outside
    it is not a large number but an invalid one.

    {2 Bounds are errors, not wrapping}

    Every operation that can leave the range returns [Error]. Nothing here
    wraps, saturates or truncates. An amount that overflowed is a transaction
    that must not be built, and silently producing a small number instead is the
    worst available outcome. *)

type t

val zero : t
val one : t

val max_bit_length : int
(** 256, from [math/int.go:16]. *)

val of_string : string -> (t, string) result
(** Parses the canonical decimal form the SDK emits: digits only, no leading
    zeros unless the value is exactly ["0"], no sign, no separators, no
    whitespace.

    Strictness is deliberate. This function reads numbers a node sent, and
    accepting ["007"] or [" 7"] would mean two spellings of one amount, which is
    a difference a policy could be shown one of and a chain the other.

    A leading ["-"] is rejected with a message that says so: [math.Int] is
    signed, but a coin amount is not — [Coin.Validate] rejects negative amounts
    ([types/coin.go:54]). *)

val to_string : t -> string
(** Canonical decimal, matching [big.Int.MarshalText]: no leading zeros, and
    ["0"] for zero. *)

val of_int : int -> (t, string) result
(** [Error] for a negative [int]. *)

val add : t -> t -> (t, string) result

val sub : t -> t -> (t, string) result
(** [Error] if [b] exceeds [a]: there are no negative amounts. *)

val mul : t -> t -> (t, string) result
val compare : t -> t -> int
val equal : t -> t -> bool
val is_zero : t -> bool

val bit_length : t -> int
(** Number of significant bits; [0] for zero. *)
