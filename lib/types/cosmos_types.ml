(** Validated primitive types for Cosmos SDK chains.

    Everything a transaction is built out of before it is a transaction:
    addresses and the three prefixes they are spelled under, amounts and the
    denominations attached to them, the fixed-point decimal a gas price is, the
    chain identifier that goes inside [SignDoc], and the per-chain profile that
    carries what differs between one Cosmos chain and the next.

    Nothing here reads a clock, draws randomness or touches a bignum. *)

module Prefix = Prefix
module Address = Address
module Amount = Amount
module Dec = Dec
module Denom = Denom
module Coin = Coin
module Chain_id = Chain_id
module Profile = Profile
