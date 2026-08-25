(* Coin amounts.

   A Cosmos amount is math.Int, capped at 256 bits, and reaching the wire as
   decimal ASCII. This closure carries no bignum on purpose, so the arithmetic
   is ours and has to be checked against something that is not.

   That something is Python's arbitrary-precision integers: the vectors below
   were computed there and pasted in. They are an oracle this library cannot
   influence, which is the same reason the address vectors come from the SDK
   rather than from here. *)

module Amount = Cosmos_types.Amount

let ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "expected Ok, got Error %S" e

let is_error what = function
  | Error _ -> ()
  | Ok _ -> Alcotest.failf "expected %s to be rejected, it was accepted" what

let a = Amount.of_string
let s = Amount.to_string

let max_256 =
  "115792089237316195423570985008687907853269984665640564039457584007913129639935"

let products =
  [
    ("1166360647", "6221083209155690086", "7256026636871667012438445642");
    ( "1628644126001261245330077470223470880",
      "12216411000036125086",
      "19896186016026028800439247436686198263610165324758495680" );
    ( "978213950346251777530308113891",
      "14081370555032444531",
      "13774593116927679527568332721552201064545688080121" );
    ( "4695879963668959402",
      "14097557316578972474",
      "66200436939597938059944532573981500548" );
    ("1902301795", "4272656795", "8127882690547447025");
    ( "160623510330002974071872900616857751736",
      "289413701808643097615555198172961679930",
      "46486644722104985010285509874241726093975610355667731351821973746101433858480"
    );
    ("10000000000000", "100000000000000", "1000000000000000000000000000");
    ( "340282366920938463463374607431768211456",
      "170141183460469231731687303715884105728",
      "57896044618658097711785492504343953926634992332820282019728792003956564819968"
    );
  ]

let sums =
  [
    ( "15766365549219733856",
      "32390531001204947386148411760513018754410056048635396201668957122984764869960",
      "32390531001204947386148411760513018754410056048635396201684723488533984603816"
    );
    ( "154618903039862433154525287960893357394498475699927156005366",
      "1540197306286426013207900391171687627460810955832099547051144",
      "1694816209326288446362425679132580984855309431532026703056510" );
    ( "950704492123077550801706314552819240080389929091037471152634",
      "13867936638623957354",
      "950704492123077550801706314552819240080403797027676095109988" );
    ( "263970131698049322952046129406022243608066478563631780513827390897938145857",
      "1547787140154479687804325325599752584268022183650506992627803",
      "263970131698050870739186283885710047933392078316216048536011041404930773660"
    );
    ( "45475575370849823113893518575344595022646180977336072145821327112798749170988",
      "4407451647428547812",
      "45475575370849823113893518575344595022646180977336072145825734564446177718800"
    );
    ( "115792089237316195423570985008687907853269984665640564039457584007913129639934",
      "1",
      "115792089237316195423570985008687907853269984665640564039457584007913129639935"
    );
  ]

let round_trips =
  [
    "0";
    "1";
    "9";
    "10";
    "255";
    "256";
    "23460";
    "1000000000000000000";
    "18446744073709551615";
    "18446744073709551616";
    "945312867037000832772241";
    "1000000000000000000000000000";
    "340282366920938463463374607431768211456";
    "80997447525449471367121528011620953405938577986792347";
    "179434758208721538898910093835288447574435954813597475";
    "48090652984610872175948112548319279355501518556970104435547698620674194767399";
    "57896044618658097711785492504343953926634992332820282019728792003956564819968";
    "65393657815994740347991480724362093243233985866614722090264484376958089915709";
    "115792089237316195423570985008687907853269984665640564039457584007913129639935";
  ]

let round_trip_is_canonical () =
  List.iter
    (fun v -> Alcotest.(check string) ("round trip " ^ v) v (s (ok (a v))))
    round_trips

let multiplication_matches_the_oracle () =
  List.iter
    (fun (x, y, expected) ->
      Alcotest.(check string)
        (x ^ " * " ^ y)
        expected
        (s (ok (Amount.mul (ok (a x)) (ok (a y)))));
      (* and it commutes, which schoolbook multiplication can get wrong at the
         carry-propagation step without the symmetric case noticing *)
      Alcotest.(check string)
        (y ^ " * " ^ x)
        expected
        (s (ok (Amount.mul (ok (a y)) (ok (a x))))))
    products

let addition_matches_the_oracle () =
  List.iter
    (fun (x, y, expected) ->
      Alcotest.(check string)
        (x ^ " + " ^ y)
        expected
        (s (ok (Amount.add (ok (a x)) (ok (a y)))));
      (* subtraction undoes it *)
      Alcotest.(check string)
        (expected ^ " - " ^ y)
        x
        (s (ok (Amount.sub (ok (a expected)) (ok (a y))))))
    sums

let the_boundary () =
  let max = ok (a max_256) in
  Alcotest.(check int) "256 significant bits" 256 (Amount.bit_length max);
  Alcotest.(check string) "and it prints back" max_256 (s max);
  (* One past the top, three ways. *)
  is_error "2^256 by addition" (Amount.add max (ok (a "1")));
  is_error "2^256 by multiplication"
    (Amount.mul
       (ok (a "340282366920938463463374607431768211456")) (* 2^128 *)
       (ok (a "340282366920938463463374607431768211456")));
  is_error "2^256 as a literal"
    (a
       "115792089237316195423570985008687907853269984665640564039457584007913129639936");
  (* Nothing wraps: the failed operations above did not leave a small number
     behind in place of a large one. *)
  Alcotest.(check string) "max is untouched" max_256 (s max)

let below_zero_is_an_error_not_a_wrap () =
  is_error "0 - 1" (Amount.sub Amount.zero Amount.one);
  is_error "3 - 4" (Amount.sub (ok (a "3")) (ok (a "4")));
  Alcotest.(check string)
    "but 4 - 4 is zero" "0"
    (s (ok (Amount.sub (ok (a "4")) (ok (a "4")))))

let only_the_canonical_spelling_is_accepted () =
  (* A node sends big.Int.MarshalText, which has exactly one spelling per
     value. Accepting a second would mean a policy could be shown one and the
     chain the other. *)
  is_error "a leading zero" (a "007");
  is_error "an empty string" (a "");
  is_error "leading whitespace" (a " 7");
  is_error "trailing whitespace" (a "7 ");
  is_error "a leading plus" (a "+7");
  is_error "an underscore separator" (a "1_000");
  is_error "a decimal point" (a "1.0");
  is_error "hexadecimal" (a "0x10");
  (* Zero is the one value that starts with a zero digit. *)
  Alcotest.(check string) "zero is spelled 0" "0" (s (ok (a "0")))

let negative_says_why () =
  match a "-1" with
  | Ok _ -> Alcotest.fail "a negative amount was accepted"
  | Error msg ->
      (* math.Int is signed; a coin amount is not, and the message should say
       that rather than "not a decimal integer". *)
      Alcotest.(check bool)
        ("the message explains, not just refuses: " ^ msg)
        true
        (Option.is_some
           (List.find_opt
              (fun sub ->
                let n = String.length sub and m = String.length msg in
                let rec at i =
                  i + n <= m && (String.sub msg i n = sub || at (i + 1))
                in
                at 0)
              [ "negative" ]))

let ordering () =
  let v = List.map (fun x -> ok (a x)) round_trips in
  (* round_trips is sorted numerically by construction, so compare must agree
     with that order -- a limb comparison that ran least-significant-first
     would not. *)
  let rec pairs = function
    | x :: (y :: _ as rest) ->
        Alcotest.(check bool) (s x ^ " < " ^ s y) true (Amount.compare x y < 0);
        pairs rest
    | _ -> ()
  in
  pairs v;
  Alcotest.(check bool)
    "equal to itself" true
    (Amount.equal (ok (a max_256)) (ok (a max_256)));
  Alcotest.(check bool) "zero is zero" true (Amount.is_zero Amount.zero);
  Alcotest.(check bool) "one is not" false (Amount.is_zero Amount.one)

let identities () =
  List.iter
    (fun v ->
      let x = ok (a v) in
      Alcotest.(check string) (v ^ " * 1") v (s (ok (Amount.mul x Amount.one)));
      Alcotest.(check string)
        (v ^ " * 0") "0"
        (s (ok (Amount.mul x Amount.zero)));
      Alcotest.(check string) (v ^ " + 0") v (s (ok (Amount.add x Amount.zero))))
    round_trips

let () =
  Alcotest.run "cosmos-amount"
    [
      ( "against Python",
        [
          Alcotest.test_case "decimal round trip" `Quick round_trip_is_canonical;
          Alcotest.test_case "multiplication" `Quick
            multiplication_matches_the_oracle;
          Alcotest.test_case "addition and subtraction" `Quick
            addition_matches_the_oracle;
        ] );
      ( "bounds",
        [
          Alcotest.test_case "the 256-bit boundary" `Quick the_boundary;
          Alcotest.test_case "below zero is an error" `Quick
            below_zero_is_an_error_not_a_wrap;
        ] );
      ( "parsing",
        [
          Alcotest.test_case "only the canonical spelling" `Quick
            only_the_canonical_spelling_is_accepted;
          Alcotest.test_case "negative says why" `Quick negative_says_why;
        ] );
      ( "algebra",
        [
          Alcotest.test_case "ordering" `Quick ordering;
          Alcotest.test_case "identities" `Quick identities;
        ] );
    ]
