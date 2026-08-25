(* Fixed-point decimals, chain ids and per-chain profiles.

   The fee vectors were computed with Python's decimal module and exact
   integer ceiling division, which is an oracle this library cannot influence.
   Fee arithmetic is the one place where being off by one base unit is not a
   rounding artefact: a fee below the node's minimum is refused outright. *)

module Dec = Cosmos_types.Dec
module Amount = Cosmos_types.Amount
module Chain_id = Cosmos_types.Chain_id
module Profile = Cosmos_types.Profile
module Coin = Cosmos_types.Coin
module Denom = Cosmos_types.Denom
module Prefix = Cosmos_types.Prefix

let ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "expected Ok, got Error %S" e

let is_error what = function
  | Error _ -> ()
  | Ok _ -> Alcotest.failf "expected %s to be rejected, it was accepted" what

let fee_vectors =
  [
    ("0.005", "200000", "1000", "5000000000000000");
    ("0.0025", "250000", "625", "2500000000000000");
    ("0.002", "100000", "200", "2000000000000000");
    ("160000000", "400000", "64000000000000", "160000000000000000000000000");
    ("0.0053", "1000000", "5300", "5300000000000000");
    ("0.000000000000000001", "1", "1", "1");
    ("0.000000000000000001", "999999999", "1", "1");
    ("1", "1", "1", "1000000000000000000");
    ("0", "500000", "0", "0");
    ("0.1", "3", "1", "100000000000000000");
    ("0.025", "200000", "5000", "25000000000000000");
    ("12345.678901234567891", "7", "86420", "12345678901234567891000");
  ]

let fees_match_the_oracle () =
  List.iter
    (fun (price, gas, expected, _) ->
      let d = ok (Dec.of_decimal_string price) in
      let g = ok (Amount.of_string gas) in
      Alcotest.(check string)
        (price ^ " * " ^ gas)
        expected
        (Amount.to_string (ok (Dec.mul_ceil d g))))
    fee_vectors

let the_wire_form_is_the_scaled_integer () =
  (* LegacyDec marshals as the integer scaled by 10^18, not as the human
     spelling. Both are the same value and confusing them is a factor of
     10^18, which is not a subtle error but is a silent one. *)
  List.iter
    (fun (price, _, _, scaled) ->
      let d = ok (Dec.of_decimal_string price) in
      Alcotest.(check string)
        (price ^ " scaled") scaled (Dec.to_scaled_string d);
      Alcotest.(check bool)
        (price ^ " round trips through the wire form")
        true
        (Dec.equal d (ok (Dec.of_scaled_string scaled))))
    fee_vectors

let the_human_form_round_trips () =
  List.iter
    (fun (price, _, _, _) ->
      let d = ok (Dec.of_decimal_string price) in
      Alcotest.(check string)
        (price ^ " round trip") price (Dec.to_decimal_string d))
    fee_vectors;
  (* Trailing zeros carry no information and are not preserved; the value is. *)
  Alcotest.(check string)
    "0.0250 normalises" "0.025"
    (Dec.to_decimal_string (ok (Dec.of_decimal_string "0.0250")));
  Alcotest.(check string)
    "1.000 normalises" "1"
    (Dec.to_decimal_string (ok (Dec.of_decimal_string "1.000")));
  Alcotest.(check string)
    "0.0 is zero" "0"
    (Dec.to_decimal_string (ok (Dec.of_decimal_string "0.0")))

let rounding_is_up_and_only_up () =
  let d = ok (Dec.of_decimal_string "0.1") in
  let at n = Amount.to_string (ok (Dec.mul_ceil d (ok (Amount.of_string n)))) in
  (* 0.1 * 10 is exactly 1 and must not become 2 ... *)
  Alcotest.(check string) "exact stays exact" "1" (at "10");
  (* ... while anything with a remainder goes up, not to nearest. *)
  Alcotest.(check string) "0.1 (up from 0.1)" "1" (at "1");
  Alcotest.(check string) "0.9 (up from 0.9)" "1" (at "9");
  Alcotest.(check string) "1.1 rounds to 2" "2" (at "11");
  Alcotest.(check string) "1.9 rounds to 2" "2" (at "19");
  Alcotest.(check string) "2.0 stays 2" "2" (at "20")

let too_many_places_is_an_error_not_a_truncation () =
  (* Nineteen places. Truncating would silently change the price. *)
  is_error "nineteen decimal places"
    (Dec.of_decimal_string "0.0000000000000000001");
  Alcotest.(check string)
    "eighteen is the limit and works" "0.000000000000000001"
    (Dec.to_decimal_string (ok (Dec.of_decimal_string "0.000000000000000001")))

let malformed_decimals () =
  is_error "empty" (Dec.of_decimal_string "");
  is_error "a bare point" (Dec.of_decimal_string ".");
  is_error "no digits before the point" (Dec.of_decimal_string ".5");
  is_error "two points" (Dec.of_decimal_string "1.2.3");
  is_error "negative" (Dec.of_decimal_string "-0.1");
  is_error "a leading zero on the whole part" (Dec.of_decimal_string "01.5");
  is_error "letters after the point" (Dec.of_decimal_string "0.1a");
  is_error "whitespace" (Dec.of_decimal_string " 0.1")

let chain_ids () =
  List.iter
    (fun c ->
      Alcotest.(check string)
        c c
        (Chain_id.to_string (ok (Chain_id.of_string c))))
    [
      "cosmoshub-4";
      "osmosis-1";
      "injective-1";
      "pion-1";
      "provider";
      "localnet";
    ];
  is_error "an empty chain id" (Chain_id.of_string "");
  Alcotest.(check int)
    "fifty characters is the limit" 50
    (String.length
       (Chain_id.to_string (ok (Chain_id.of_string (String.make 50 'a')))));
  is_error "fifty-one characters" (Chain_id.of_string (String.make 51 'a'))

let committed_profiles_are_coherent () =
  List.iter
    (fun p ->
      let base = Profile.base_prefix p in
      Alcotest.(check string)
        (base ^ " account prefix") base
        (Prefix.to_string (Profile.account_prefix p));
      Alcotest.(check string)
        (base ^ " validator prefix")
        (base ^ "valoper")
        (Prefix.to_string (Profile.validator_prefix p));
      Alcotest.(check string)
        (base ^ " consensus prefix")
        (base ^ "valcons")
        (Prefix.to_string (Profile.consensus_prefix p));
      (* A fee is quotable on every profile, and lands in the fee denom. *)
      let fee =
        ok (Profile.fee_for_gas p ~gas:(ok (Amount.of_string "200000")))
      in
      Alcotest.(check bool)
        (base ^ " fee is in the fee denom")
        true
        (Denom.equal (Coin.denom fee) (Profile.fee_denom p)))
    Profile.all

let the_hub_and_osmosis_fees () =
  (* Two chains, one envelope, different answers -- which is the point of a
     profile. Both at the 200000 gas a simple transfer takes. *)
  let gas = ok (Amount.of_string "200000") in
  Alcotest.(check string)
    "cosmos hub" "1000uatom"
    (Coin.to_string (ok (Profile.fee_for_gas Profile.cosmos_hub ~gas)));
  Alcotest.(check string)
    "osmosis" "500uosmo"
    (Coin.to_string (ok (Profile.fee_for_gas Profile.osmosis ~gas)));
  (* Injective prices gas in an eighteen-decimal token, so its fee is a number
     that does not fit in sixty-four bits' worth of base units at any realistic
     gas limit. *)
  let big = ok (Amount.of_string "50000000") in
  let inj = ok (Profile.fee_for_gas Profile.injective ~gas:big) in
  Alcotest.(check string) "injective" "8000000000000000inj" (Coin.to_string inj)

let a_profile_will_not_take_a_bad_prefix () =
  let hub = Profile.cosmos_hub in
  is_error "an upper-case prefix"
    (Profile.make ~chain_id:(Profile.chain_id hub) ~base_prefix:"Cosmos"
       ~fee_denom:(Profile.fee_denom hub) ~fee_exponent:6
       ~min_gas_price:(Profile.min_gas_price hub));
  is_error "an exponent past eighteen"
    (Profile.make ~chain_id:(Profile.chain_id hub) ~base_prefix:"cosmos"
       ~fee_denom:(Profile.fee_denom hub) ~fee_exponent:19
       ~min_gas_price:(Profile.min_gas_price hub))

let () =
  Alcotest.run "cosmos-profile"
    [
      ( "dec against the oracle",
        [
          Alcotest.test_case "fees" `Quick fees_match_the_oracle;
          Alcotest.test_case "the wire form is scaled" `Quick
            the_wire_form_is_the_scaled_integer;
          Alcotest.test_case "the human form round trips" `Quick
            the_human_form_round_trips;
        ] );
      ( "dec rules",
        [
          Alcotest.test_case "rounding is up, and only up" `Quick
            rounding_is_up_and_only_up;
          Alcotest.test_case "too many places is an error" `Quick
            too_many_places_is_an_error_not_a_truncation;
          Alcotest.test_case "malformed" `Quick malformed_decimals;
        ] );
      ("chain id", [ Alcotest.test_case "length and content" `Quick chain_ids ]);
      ( "profile",
        [
          Alcotest.test_case "the committed ones are coherent" `Quick
            committed_profiles_are_coherent;
          Alcotest.test_case "two chains, different fees" `Quick
            the_hub_and_osmosis_fees;
          Alcotest.test_case "a bad prefix is refused" `Quick
            a_profile_will_not_take_a_bad_prefix;
        ] );
    ]
