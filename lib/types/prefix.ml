type kind = Account | Validator | Consensus
type t = { hrp : string; kind : kind }

let make ~base:_ _kind = Error "cosmos-types: Prefix.make is not implemented"
let to_string t = t.hrp
let kind t = t.kind
