module Amount = Cosmos_types.Amount
module Coin = Cosmos_types.Coin
module Denom = Cosmos_types.Denom
module Profile = Cosmos_types.Profile

let adjust_gas ~simulated ~multiplier =
  if simulated <= 0L then Error "fees: simulated gas must be positive"
  else if multiplier < 1.0 then
    Error
      (Printf.sprintf
         "fees: a multiplier of %g asks for less gas than the simulation used"
         multiplier)
  else
    let scaled = Int64.of_float (Int64.to_float simulated *. multiplier) in
    if scaled < simulated then Error "fees: the adjusted gas limit overflowed"
    else Ok scaled

let for_gas profile ~gas =
  match Amount.of_int (Int64.to_int gas) with
  | Error e -> Error e
  | Ok gas -> Profile.fee_for_gas profile ~gas

let covers ~fee profile ~gas =
  match for_gas profile ~gas with
  | Error _ -> false
  | Ok minimum ->
      Denom.equal (Coin.denom fee) (Coin.denom minimum)
      && Amount.compare (Coin.amount fee) (Coin.amount minimum) >= 0
