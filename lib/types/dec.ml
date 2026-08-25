(* An integer scaled by 10^18, carried in an Amount. math/legacy_dec.go:20-21.

   10^18 does not fit Amount.divmod_small's bound of 10^9, so scaling up and
   down is done in two steps of 10^9. That is exact -- 10^18 = 10^9 * 10^9 --
   and the remainders recombine as r2 * 10^9 + r1, which is what mul_ceil
   needs to know whether anything was rounded away. *)

let precision = 18
let half_scale = 1_000_000_000 (* 10^9 *)

type t = Amount.t (* the scaled value *)

let zero = Amount.zero
let is_zero = Amount.is_zero
let compare = Amount.compare
let equal = Amount.equal
let of_scaled_string = Amount.of_string
let to_scaled_string = Amount.to_string

let of_decimal_string s =
  let n = String.length s in
  if n = 0 then Error "dec: empty"
  else begin
    let whole, frac =
      match String.index_opt s '.' with
      | None -> (s, "")
      | Some i -> (String.sub s 0 i, String.sub s (i + 1) (n - i - 1))
    in
    if whole = "" then
      Error (Printf.sprintf "dec: %S has no digits before the point" s)
    else if String.contains frac '.' then
      Error (Printf.sprintf "dec: %S has more than one point" s)
    else if String.length frac > precision then
      Error
        (Printf.sprintf "dec: %S has %d decimal places; the maximum is %d" s
           (String.length frac) precision)
    else if
      frac <> "" && not (String.for_all (fun c -> c >= '0' && c <= '9') frac)
    then Error (Printf.sprintf "dec: %S has a non-digit after the point" s)
    else
      (* Amount.of_string does the canonical-decimal checking for the whole
         part, including refusing a leading zero and a sign. *)
      match Amount.of_string whole with
      | Error e -> Error e
      | Ok w -> (
          let padded =
            frac ^ String.make (precision - String.length frac) '0'
          in
          (* [padded] is exactly 18 digits, so it always parses; the leading-zero
           rule does not apply because it is a fraction, not an integer. *)
          let frac_value =
            let rec go acc i =
              if i = String.length padded then Ok acc
              else
                match Amount.mul acc (Result.get_ok (Amount.of_int 10)) with
                | Error _ as e -> e
                | Ok acc -> (
                    match
                      Amount.of_int (Char.code padded.[i] - Char.code '0')
                    with
                    | Error _ as e -> e
                    | Ok d -> (
                        match Amount.add acc d with
                        | Error _ as e -> e
                        | Ok acc -> go acc (i + 1)))
            in
            go Amount.zero 0
          in
          match frac_value with
          | Error _ as e -> e
          | Ok f -> (
              (* w * 10^18 + f, in two steps of 10^9. *)
              let ten9 = Result.get_ok (Amount.of_int half_scale) in
              match Amount.mul w ten9 with
              | Error _ as e -> e
              | Ok x -> (
                  match Amount.mul x ten9 with
                  | Error _ as e -> e
                  | Ok x -> Amount.add x f)))
  end

let to_decimal_string t =
  match Amount.divmod_small t half_scale with
  | Error e -> e (* unreachable: half_scale is in range *)
  | Ok (q1, r1) -> (
      match Amount.divmod_small q1 half_scale with
      | Error e -> e
      | Ok (whole, r2) ->
          let frac = Printf.sprintf "%09d%09d" r2 r1 in
          (* Trailing zeros carry no information in a decimal fraction. *)
          let rec trim i =
            if i > 0 && frac.[i - 1] = '0' then trim (i - 1) else i
          in
          let keep = trim precision in
          if keep = 0 then Amount.to_string whole
          else Amount.to_string whole ^ "." ^ String.sub frac 0 keep)

let mul_ceil t n =
  match Amount.mul t n with
  | Error _ as e -> e
  | Ok scaled -> (
      match Amount.divmod_small scaled half_scale with
      | Error _ as e -> e
      | Ok (q1, r1) -> (
          match Amount.divmod_small q1 half_scale with
          | Error _ as e -> e
          | Ok (q, r2) ->
              (* Anything left in either remainder means the true value was above q,
           so the ceiling is one more. *)
              if r1 = 0 && r2 = 0 then Ok q else Amount.add q Amount.one))
