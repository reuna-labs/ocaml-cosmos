(* Properties of the 256-bit arithmetic.

   The vectors in test_amount.ml pin specific values against Python. These
   cover the space between them, which is where a carry or borrow that is
   wrong only at a limb boundary hides: sixteen-bit limbs put a boundary every
   65536, and a hand-picked vector is unlikely to land on one. *)

module Amount = Cosmos_types.Amount

let ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "expected Ok, got Error %S" e

(* Decimal strings of values that straddle limb boundaries, powers of two and
   the top of the range, rather than uniform random ones -- which would almost
   always be 250-odd bits and never near a carry. *)
let gen_decimal =
  let open QCheck2.Gen in
  let* shape = int_range 0 4 in
  let* bits = int_range 0 255 in
  let* delta = int_range 0 4 in
  let+ small = int_range 0 100_000 in
  let ( ** ) b e =
    (* b^e as a decimal string, by repeated doubling on strings would be slow;
       these are built from the library's own multiplication, which the vector
       tests have already checked against Python. *)
    let rec go acc n =
      if n = 0 then acc else go (ok (Amount.mul acc b)) (n - 1)
    in
    go Amount.one e
  in
  let two = ok (Amount.of_int 2) in
  let pow2 n = two ** n in
  let v =
    match shape with
    | 0 -> ok (Amount.of_int small)
    | 1 -> pow2 bits
    | 2 -> (
        (* just below a power of two: every low limb is 0xFFFF *)
        match Amount.sub (pow2 bits) (ok (Amount.of_int (delta + 1))) with
        | Ok v -> v
        | Error _ -> Amount.zero)
    | 3 -> (
        match Amount.add (pow2 bits) (ok (Amount.of_int delta)) with
        | Ok v -> v
        | Error _ -> pow2 bits)
    | _ -> (
        (* just below the maximum *)
        let max =
          ok
            (Amount.of_string
               "115792089237316195423570985008687907853269984665640564039457584007913129639935")
        in
        match Amount.sub max (ok (Amount.of_int small)) with
        | Ok v -> v
        | Error _ -> max)
  in
  Amount.to_string v

(* QCheck2 takes a generator directly; printing is a separate optional
   argument, and passing it is what makes a counterexample readable. *)
let pair = QCheck2.Gen.pair gen_decimal gen_decimal
let print_pair (x, y) = x ^ " , " ^ y
let a s = ok (Amount.of_string s)

let round_trip =
  QCheck2.Test.make ~count:2000 ~name:"decimal round trip is the identity"
    ~print:Fun.id gen_decimal (fun s -> Amount.to_string (a s) = s)

let add_then_sub =
  QCheck2.Test.make ~count:2000 ~name:"(x + y) - y = x" ~print:print_pair pair
    (fun (x, y) ->
      match Amount.add (a x) (a y) with
      | Error _ -> true (* overflow is a legitimate outcome, not a failure *)
      | Ok sum -> Amount.equal (ok (Amount.sub sum (a y))) (a x))

let mul_commutes =
  QCheck2.Test.make ~count:1000 ~name:"x * y = y * x" ~print:print_pair pair
    (fun (x, y) ->
      match (Amount.mul (a x) (a y), Amount.mul (a y) (a x)) with
      | Ok p, Ok q -> Amount.equal p q
      | Error _, Error _ -> true
      | _ -> false)

let mul_distributes =
  (* x * (y + 1) = x * y + x. Catches a carry that is dropped only when the
     addition inside the multiplication crosses a limb. *)
  QCheck2.Test.make ~count:1000 ~name:"x * (y + 1) = x * y + x"
    ~print:print_pair pair (fun (x, y) ->
      let x = a x and y = a y in
      match Amount.add y Amount.one with
      | Error _ -> true
      | Ok y1 -> (
          match (Amount.mul x y1, Amount.mul x y) with
          | Ok left, Ok xy -> (
              match Amount.add xy x with
              | Ok right -> Amount.equal left right
              | Error _ -> false)
          | Error _, _ -> true (* overflowed on the larger side, fine *)
          | Ok _, Error _ -> false))

let compare_is_a_total_order =
  QCheck2.Test.make ~count:2000
    ~name:"compare agrees with decimal length then digits" ~print:print_pair
    pair (fun (x, y) ->
      let cx = a x and cy = a y in
      let c = Amount.compare cx cy in
      (* Canonical decimals compare numerically by length, then lexically. *)
      let expected =
        if String.length x <> String.length y then
          Stdlib.compare (String.length x) (String.length y)
        else Stdlib.compare x y
      in
      Stdlib.compare c 0 = Stdlib.compare expected 0)

let sub_is_never_negative =
  QCheck2.Test.make ~count:2000 ~name:"x - y errors exactly when y > x"
    ~print:print_pair pair (fun (x, y) ->
      let cx = a x and cy = a y in
      match Amount.sub cx cy with
      | Ok d ->
          Amount.compare cy cx <= 0 && Amount.equal (ok (Amount.add d cy)) cx
      | Error _ -> Amount.compare cy cx > 0)

let divmod_reconstructs =
  QCheck2.Test.make ~count:1000 ~name:"q * d + r = x, and r < d"
    ~print:(fun (x, d) -> x ^ " / " ^ string_of_int d)
    (QCheck2.Gen.pair gen_decimal
       (QCheck2.Gen.map
          (fun n -> 1 + (abs n mod 1_000_000_000))
          QCheck2.Gen.int))
    (fun (x, d) ->
      let cx = a x in
      match Amount.divmod_small cx d with
      | Error _ -> false
      | Ok (q, r) -> (
          r >= 0 && r < d
          &&
          match Amount.mul q (ok (Amount.of_int d)) with
          | Error _ -> false
          | Ok qd -> (
              match Amount.add qd (ok (Amount.of_int r)) with
              | Ok back -> Amount.equal back cx
              | Error _ -> false)))

let () =
  Alcotest.run "cosmos-amount-properties"
    [
      ( "arithmetic",
        List.map
          (QCheck_alcotest.to_alcotest ~verbose:false)
          [
            round_trip;
            add_then_sub;
            mul_commutes;
            mul_distributes;
            compare_is_a_total_order;
            sub_is_never_negative;
            divmod_reconstructs;
          ] );
    ]
