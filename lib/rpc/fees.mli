(** Turning gas into a fee.

    A fee is a gas limit times a gas price, rounded up, and both halves are
    somebody's decision rather than this library's. The gas limit comes from a
    simulation or from a caller who knows what the transaction costs; the price
    comes from the chain profile or from what the node says it wants.

    {2 Why the multiplier is explicit}

    A simulated gas figure is what the transaction used {i in the simulation}.
    Execution against a slightly different state can use more, so every client
    multiplies before submitting. That multiplier is a judgement about how much
    to overpay to avoid a failure, so it is a parameter rather than a constant
    hidden in here. *)

module Amount = Cosmos_types.Amount
module Coin = Cosmos_types.Coin
module Profile = Cosmos_types.Profile

val adjust_gas : simulated:int64 -> multiplier:float -> (int64, string) result
(** [Error] for a multiplier below 1, which asks for a limit under what the
    simulation already used, and for a result that overflows. *)

val for_gas : Profile.t -> gas:int64 -> (Coin.t, string) result
(** The chain's minimum fee for [gas] units. A floor, not a quotation: a
    particular node may want more. *)

val covers : fee:Coin.t -> Profile.t -> gas:int64 -> bool
(** Whether [fee] is at least the chain's minimum for [gas]. What a policy asks
    before approving a fee that a caller supplied rather than computed. *)
