type t =
  | Transport of string
  | Malformed of string
  | Rpc of { code : int; message : string }
  | Abci of { code : int; codespace : string; log : string }

let to_string = function
  | Transport m -> "transport: " ^ m
  | Malformed m -> "malformed response: " ^ m
  | Rpc { code; message } -> Printf.sprintf "rpc error %d: %s" code message
  | Abci { code; codespace; log } ->
      Printf.sprintf "abci error %d (%s): %s" code codespace log

let pp ppf t = Format.pp_print_string ppf (to_string t)
let is_retryable = function Transport _ -> true | _ -> false
