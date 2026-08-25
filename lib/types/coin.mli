(** A denominated amount.

    [Coin.Validate] at the pinned revision ([types/coin.go:45-59]) requires a
    valid denomination and a non-negative, non-nil amount, and that is the whole
    of it. Note what it does not require: the amount may be zero, and a zero
    coin is valid and appears on the wire.

    {2 Coins do not add}

    There is deliberately no [add] taking two coins. Adding [1uatom] to [1uosmo]
    has no meaning, and a function that returned a result for it — or raised —
    would be an invitation to write the mistake. Amounts add;
    {!Cosmos_types.Amount} is where that lives, and a caller that has
    established the denominations match can use it. *)

type t

val make : denom:Denom.t -> amount:Amount.t -> t
val denom : t -> Denom.t
val amount : t -> Amount.t

val of_strings : denom:string -> amount:string -> (t, string) result
(** The wire form of both halves, validated. *)

val to_string : t -> string
(** The SDK's spelling: the amount then the denomination, no space, as in
    ["1000uatom"]. *)

val is_zero : t -> bool
val equal : t -> t -> bool
