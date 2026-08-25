(* A 256-bit unsigned integer, as sixteen 16-bit limbs, least significant
   first.

   Sixteen bits rather than thirty-two is forced by multiplication. OCaml's
   native int holds 63 bits, and a product of two 32-bit limbs reaches 2^64,
   which does not fit; a product of two 16-bit limbs reaches 2^32, and even
   accumulating sixteen of them with carry stays under 2^37. Thirty-two-bit
   limbs would need Int64 and explicit carry detection, which is more code and
   more places to be subtly wrong. *)

let limbs = 16
let limb_bits = 16
let limb_mask = 0xFFFF
let max_bit_length = limbs * limb_bits

type t = int array (* length [limbs], each element 0..0xFFFF *)

let make () = Array.make limbs 0
let zero = make ()

let one =
  let a = make () in
  a.(0) <- 1;
  a

let is_zero a = Array.for_all (fun l -> l = 0) a

let compare a b =
  let rec go i =
    if i < 0 then 0
    else if a.(i) <> b.(i) then Stdlib.compare a.(i) b.(i)
    else go (i - 1)
  in
  go (limbs - 1)

let equal a b = compare a b = 0

let bit_length a =
  let rec go i =
    if i < 0 then 0
    else if a.(i) = 0 then go (i - 1)
    else begin
      let rec bits n acc = if n = 0 then acc else bits (n lsr 1) (acc + 1) in
      (i * limb_bits) + bits a.(i) 0
    end
  in
  go (limbs - 1)

let overflow = Error "amount: exceeds the 256-bit maximum"

let add a b =
  let r = make () in
  let carry = ref 0 in
  for i = 0 to limbs - 1 do
    let s = a.(i) + b.(i) + !carry in
    r.(i) <- s land limb_mask;
    carry := s lsr limb_bits
  done;
  if !carry <> 0 then overflow else Ok r

let sub a b =
  let r = make () in
  let borrow = ref 0 in
  for i = 0 to limbs - 1 do
    let s = a.(i) - b.(i) - !borrow in
    if s < 0 then begin
      r.(i) <- s + (limb_mask + 1);
      borrow := 1
    end
    else begin
      r.(i) <- s;
      borrow := 0
    end
  done;
  if !borrow <> 0 then
    Error
      "amount: subtraction would be negative, and there are no negative amounts"
  else Ok r

let mul a b =
  (* Schoolbook into twice the width; anything landing above the top limb is
     the overflow, and is reported rather than dropped. *)
  let wide = Array.make (2 * limbs) 0 in
  for i = 0 to limbs - 1 do
    if a.(i) <> 0 then begin
      let carry = ref 0 in
      for j = 0 to limbs - 1 do
        let cur = wide.(i + j) + (a.(i) * b.(j)) + !carry in
        wide.(i + j) <- cur land limb_mask;
        carry := cur lsr limb_bits
      done;
      (* Propagate the last carry past the inner loop. *)
      let k = ref (i + limbs) in
      while !carry <> 0 do
        let cur = wide.(!k) + !carry in
        wide.(!k) <- cur land limb_mask;
        carry := cur lsr limb_bits;
        incr k
      done
    end
  done;
  let spilled = ref false in
  for i = limbs to (2 * limbs) - 1 do
    if wide.(i) <> 0 then spilled := true
  done;
  if !spilled then overflow else Ok (Array.sub wide 0 limbs)

(* [a * m + d] in place, for parsing. [m] and [d] are small. *)
let mul_small_add a m d =
  let r = make () in
  let carry = ref d in
  for i = 0 to limbs - 1 do
    let cur = (a.(i) * m) + !carry in
    r.(i) <- cur land limb_mask;
    carry := cur lsr limb_bits
  done;
  if !carry <> 0 then overflow else Ok r

(* [a / d] and [a mod d], for printing. [d] is small enough that
   [rem * 2^16 + limb] stays well inside a native int. *)
let divmod_small_unchecked a d =
  let q = make () in
  let rem = ref 0 in
  for i = limbs - 1 downto 0 do
    let cur = (!rem lsl limb_bits) lor a.(i) in
    q.(i) <- cur / d;
    rem := cur mod d
  done;
  (q, !rem)

let max_small_divisor = 1_000_000_000

let divmod_small a d =
  if d < 1 || d > max_small_divisor then
    Error
      (Printf.sprintf "amount: divisor must be in 1..%d, got %d"
         max_small_divisor d)
  else Ok (divmod_small_unchecked a d)

let of_int n =
  if n < 0 then Error "amount: negative"
  else begin
    let r = make () in
    let v = ref n in
    let i = ref 0 in
    while !v <> 0 && !i < limbs do
      r.(!i) <- !v land limb_mask;
      v := !v lsr limb_bits;
      incr i
    done;
    if !v <> 0 then overflow else Ok r
  end

let of_string s =
  let n = String.length s in
  if n = 0 then Error "amount: empty"
  else if s.[0] = '-' then
    Error "amount: negative, but a coin amount cannot be negative"
  else if s.[0] = '+' then Error "amount: leading '+'"
  else if not (String.for_all (fun c -> c >= '0' && c <= '9') s) then
    Error (Printf.sprintf "amount: %S is not a decimal integer" s)
  else if n > 1 && s.[0] = '0' then
    Error
      (Printf.sprintf "amount: %S has a leading zero, which is not canonical" s)
  else begin
    let rec go acc i =
      if i = n then Ok acc
      else
        match mul_small_add acc 10 (Char.code s.[i] - Char.code '0') with
        | Error _ as e -> e
        | Ok acc -> go acc (i + 1)
    in
    go zero 0
  end

let to_string a =
  if is_zero a then "0"
  else begin
    (* Nine digits at a time: 10^9 keeps [rem * 2^16 + limb] tiny, and 256
       bits is 78 decimal digits, so this runs nine times. *)
    let chunk = 1_000_000_000 in
    let buf = Buffer.create 80 in
    let parts = ref [] in
    let cur = ref a in
    while not (is_zero !cur) do
      let q, r = divmod_small_unchecked !cur chunk in
      parts := r :: !parts;
      cur := q
    done;
    (match !parts with
    | [] -> Buffer.add_char buf '0'
    | first :: rest ->
        Buffer.add_string buf (string_of_int first);
        List.iter
          (fun p -> Buffer.add_string buf (Printf.sprintf "%09d" p))
          rest);
    Buffer.contents buf
  end
