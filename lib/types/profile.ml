type t = {
  chain_id : Chain_id.t;
  base_prefix : string;
  fee_denom : Denom.t;
  fee_exponent : int;
  min_gas_price : Dec.t;
  account_prefix : Prefix.t;
  validator_prefix : Prefix.t;
  consensus_prefix : Prefix.t;
}

let make ~chain_id ~base_prefix ~fee_denom ~fee_exponent ~min_gas_price =
  if fee_exponent < 0 || fee_exponent > 18 then
    Error
      (Printf.sprintf "profile: fee exponent %d is outside 0..18" fee_exponent)
  else
    match Prefix.make ~base:base_prefix Prefix.Account with
    | Error _ as e -> e
    | Ok account_prefix -> (
        match Prefix.make ~base:base_prefix Prefix.Validator with
        | Error _ as e -> e
        | Ok validator_prefix -> (
            match Prefix.make ~base:base_prefix Prefix.Consensus with
            | Error _ as e -> e
            | Ok consensus_prefix ->
                Ok
                  {
                    chain_id;
                    base_prefix;
                    fee_denom;
                    fee_exponent;
                    min_gas_price;
                    account_prefix;
                    validator_prefix;
                    consensus_prefix;
                  }))

let chain_id t = t.chain_id
let base_prefix t = t.base_prefix
let fee_denom t = t.fee_denom
let fee_exponent t = t.fee_exponent
let min_gas_price t = t.min_gas_price
let account_prefix t = t.account_prefix
let validator_prefix t = t.validator_prefix
let consensus_prefix t = t.consensus_prefix

let fee_for_gas t ~gas =
  match Dec.mul_ceil t.min_gas_price gas with
  | Error _ as e -> e
  | Ok amount -> Ok (Coin.make ~denom:t.fee_denom ~amount)

(* The committed profiles. Every one of these is built through [make], so a
   typo in a prefix or a denomination fails to compile the library rather than
   producing a profile nobody checked. *)
let profile ~chain_id ~base_prefix ~fee_denom ~fee_exponent ~min_gas_price =
  match
    ( Chain_id.of_string chain_id,
      Denom.of_string fee_denom,
      Dec.of_decimal_string min_gas_price )
  with
  | Ok chain_id, Ok fee_denom, Ok min_gas_price -> (
      match
        make ~chain_id ~base_prefix ~fee_denom ~fee_exponent ~min_gas_price
      with
      | Ok p -> p
      | Error e -> invalid_arg ("profile: " ^ e))
  | Error e, _, _ | _, Error e, _ | _, _, Error e ->
      invalid_arg ("profile: " ^ e)

let cosmos_hub =
  profile ~chain_id:"cosmoshub-4" ~base_prefix:"cosmos" ~fee_denom:"uatom"
    ~fee_exponent:6 ~min_gas_price:"0.005"

let osmosis =
  profile ~chain_id:"osmosis-1" ~base_prefix:"osmo" ~fee_denom:"uosmo"
    ~fee_exponent:6 ~min_gas_price:"0.0025"

let celestia =
  profile ~chain_id:"celestia" ~base_prefix:"celestia" ~fee_denom:"utia"
    ~fee_exponent:6 ~min_gas_price:"0.002"

let injective =
  profile ~chain_id:"injective-1" ~base_prefix:"inj" ~fee_denom:"inj"
    ~fee_exponent:18 ~min_gas_price:"160000000"

let neutron =
  profile ~chain_id:"neutron-1" ~base_prefix:"neutron" ~fee_denom:"untrn"
    ~fee_exponent:6 ~min_gas_price:"0.0053"

let cosmos_hub_testnet =
  profile ~chain_id:"provider" ~base_prefix:"cosmos" ~fee_denom:"uatom"
    ~fee_exponent:6 ~min_gas_price:"0.005"

let all =
  [ cosmos_hub; osmosis; celestia; injective; neutron; cosmos_hub_testnet ]
