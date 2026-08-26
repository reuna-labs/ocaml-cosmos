type t =
  | Unknown
  | In_mempool
  | Delivered of { height : int64 }
  | Final of { height : int64; depth : int }
  | Failed of { code : int; codespace : string; log : string }

let of_broadcast (r : Method.broadcast_result) =
  if r.code = 0 then In_mempool
  else Failed { code = r.code; codespace = r.codespace; log = r.log }

let of_tx (r : Method.tx_result) ~tip ~required_depth =
  if r.code <> 0 then
    Failed { code = r.code; codespace = r.codespace; log = r.log }
  else
    (* A node reporting a height above its own tip has contradicted itself.
       Believing the larger number and calling it deeply confirmed would be
       exactly backwards, so this falls back to Delivered. *)
    let depth = Int64.sub tip r.height in
    if depth < 0L then Delivered { height = r.height }
    else
      let depth =
        if depth > Int64.of_int max_int then max_int else Int64.to_int depth
      in
      if depth >= required_depth then Final { height = r.height; depth }
      else Delivered { height = r.height }

let is_final = function Final _ -> true | _ -> false
let is_settled = function Final _ | Failed _ -> true | _ -> false

let pp ppf = function
  | Unknown -> Format.pp_print_string ppf "unknown"
  | In_mempool ->
      Format.pp_print_string ppf "in a mempool (not executed, may still fail)"
  | Delivered { height } -> Format.fprintf ppf "delivered at height %Ld" height
  | Final { height; depth } ->
      Format.fprintf ppf "final at height %Ld, %d block(s) deep" height depth
  | Failed { code; codespace; log } ->
      Format.fprintf ppf "failed with %s code %d: %s" codespace code log
