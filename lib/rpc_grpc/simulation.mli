(** What a simulation says a transaction would cost.

    [gas_used] is what the transaction used {i in the simulation}. Execution
    against a slightly different state can use more, so it is a measurement and
    not a limit — {!Cosmos_rpc.Fees.adjust_gas} is what turns it into one, and
    it takes the multiplier as an argument because how much to overpay to avoid
    a failure is a product decision. *)

type t = { gas_wanted : int64; gas_used : int64 }
