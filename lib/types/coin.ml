type t = { denom : Denom.t; amount : Amount.t }

let make ~denom ~amount = { denom; amount }
let denom t = t.denom
let amount t = t.amount

let of_strings ~denom ~amount =
  match Denom.of_string denom with
  | Error _ as e -> e
  | Ok denom -> (
      match Amount.of_string amount with
      | Error _ as e -> e
      | Ok amount -> Ok { denom; amount })

let to_string t = Amount.to_string t.amount ^ Denom.to_string t.denom
let is_zero t = Amount.is_zero t.amount
let equal a b = Denom.equal a.denom b.denom && Amount.equal a.amount b.amount
