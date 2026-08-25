(** Chain identifiers.

    A chain id is a string of 1 to 50 characters ([MaxChainIDLen] in CometBFT
    [types/genesis.go:20], with the emptiness and length checks at [:70-75]).
    CometBFT imposes no other rule, and neither does this: [cosmoshub-4],
    [osmosis-1], [injective-1] and [pion-1] follow a name-number convention that
    is not enforced anywhere and that a test chain will happily ignore.

    {2 Why it is a type}

    Because it is inside [SignDoc]. The chain id is what stops a transaction
    signed for a testnet from being replayed on the chain it mirrors, so it is
    not a label attached to a request — it is signed data, and a caller that can
    confuse two of them has lost the protection. *)

type t

val of_string : string -> (t, string) result
val to_string : t -> string
val equal : t -> t -> bool

val max_length : int
(** 50. *)
