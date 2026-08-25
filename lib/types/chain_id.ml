type t = string

(* CometBFT types/genesis.go:20 at the pinned revision. *)
let max_length = 50

let of_string s =
  let n = String.length s in
  if n = 0 then Error "chain_id: empty"
  else if n > max_length then
    Error
      (Printf.sprintf "chain_id: %d characters; the maximum is %d" n max_length)
  else Ok s

let to_string t = t
let equal = String.equal
