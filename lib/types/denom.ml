type t = string

(* types/coin.go:848 at the pinned revision:
     [a-zA-Z][a-zA-Z0-9/:._-]{2,127}
   anchored at both ends. Three to 128 characters inclusive. *)

let min_length = 3
let max_length = 128
let is_letter c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
let is_digit c = c >= '0' && c <= '9'

let is_tail c =
  is_letter c || is_digit c || c = '/' || c = ':' || c = '.' || c = '_'
  || c = '-'

let of_string s =
  let n = String.length s in
  if n < min_length || n > max_length then
    Error
      (Printf.sprintf "denom: %S is %d characters; the range is %d to %d" s n
         min_length max_length)
  else if not (is_letter s.[0]) then
    Error (Printf.sprintf "denom: %S must start with a letter" s)
  else begin
    let bad = ref None in
    String.iteri
      (fun i c -> if i > 0 && !bad = None && not (is_tail c) then bad := Some c)
      s;
    match !bad with
    | Some c -> Error (Printf.sprintf "denom: %S contains %C" s c)
    | None -> Ok s
  end

let to_string t = t
let equal = String.equal
let is_ibc_voucher t = String.length t > 4 && String.sub t 0 4 = "ibc/"
