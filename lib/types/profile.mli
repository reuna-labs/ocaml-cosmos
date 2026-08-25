(** What differs between one Cosmos chain and the next.

    The transaction envelope is identical across the ecosystem. What is not is
    the bech32 prefix, the chain id, which denomination fees are paid in, and
    what the validators charge per unit of gas. Roughly a hundred app-chains
    differ in exactly those four things and agree on everything else, which is
    why a chain is a record here and never a branch in the code.

    {2 Getting one wrong is not a compile error}

    It is a rejected transaction, an overpaid fee, or — where two chains share a
    prefix convention — a correctly signed message sent somewhere it was not
    meant to go. A profile deserves the same fixture discipline as a codec.

    The committed profiles below are a convenience for testing and examples.
    They are not authoritative: gas prices are governance parameters and move. A
    product reads them from configuration it controls. *)

type t

val make :
  chain_id:Chain_id.t ->
  base_prefix:string ->
  fee_denom:Denom.t ->
  fee_exponent:int ->
  min_gas_price:Dec.t ->
  (t, string) result
(** [fee_exponent] is how many decimal places separate the base unit from the
    display unit — 6 for [uatom] against [ATOM], 18 for [ainj] against [INJ]. It
    is here so that an intent can be explained to a human, and is used for
    nothing else. *)

val chain_id : t -> Chain_id.t
val base_prefix : t -> string
val fee_denom : t -> Denom.t
val fee_exponent : t -> int
val min_gas_price : t -> Dec.t
val account_prefix : t -> Prefix.t
val validator_prefix : t -> Prefix.t
val consensus_prefix : t -> Prefix.t

val fee_for_gas : t -> gas:Amount.t -> (Coin.t, string) result
(** The minimum fee this chain's default configuration would accept for [gas]
    units, rounded up. A node may be configured to want more; this is a floor,
    not a quotation. *)

(** {2 Committed profiles}

    Convenience, not authority. See the note above. *)

val cosmos_hub : t
val osmosis : t
val celestia : t
val injective : t
val neutron : t
val cosmos_hub_testnet : t
val all : t list
