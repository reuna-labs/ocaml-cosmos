type private_key = unit
type public_key = unit
type signature = unit

let not_implemented what =
  Error ("cosmos-crypto: " ^ what ^ " is not implemented")

let sign_digest ~key:_ _digest = not_implemented "sign_digest"
let verify_digest ~key:_ _sig _digest = false
let is_low_s _ = false
let public_key_of_private _ = ()
let compressed _ = ""
let address_bytes _ = ""
