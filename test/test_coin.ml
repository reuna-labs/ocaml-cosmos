(* Denominations and coins.

   The rule for a denomination is one regular expression in the SDK
   (types/coin.go:848); these cases walk its edges, since matching it by hand
   is the sort of thing that is right for every name anyone tries and wrong at
   a boundary. *)

module Denom = Cosmos_types.Denom
module Coin = Cosmos_types.Coin
module Amount = Cosmos_types.Amount

let ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "expected Ok, got Error %S" e

let is_error what = function
  | Error _ -> ()
  | Ok _ -> Alcotest.failf "expected %s to be rejected, it was accepted" what

let real_denominations () =
  (* What the launch chains actually use, including an IBC voucher. *)
  List.iter
    (fun d ->
      Alcotest.(check string) d d (Denom.to_string (ok (Denom.of_string d))))
    [
      "uatom";
      "uosmo";
      "utia";
      "inj";
      "adydx";
      "untrn";
      "uusdc";
      "stake";
      "ibc/27394FB092D2ECCD56123C74F36E4C1F926001CEADA9CA97EA622B25F41E5EB2";
      "factory/osmo1z0qrq605sjgcqpylfl4aa6s90x738j7m58wyatt0tdzflg2ha26q67k743/wbtc";
      "gamm/pool/1";
      "erc20/0x1234";
      "transfer/channel-0/uatom";
    ]

let the_length_boundary () =
  (* 3 to 128 inclusive. *)
  is_error "two characters" (Denom.of_string "ua");
  Alcotest.(check string)
    "three is fine" "uat"
    (Denom.to_string (ok (Denom.of_string "uat")));
  let at n = "a" ^ String.make (n - 1) 'b' in
  Alcotest.(check string)
    "128 is fine" (at 128)
    (Denom.to_string (ok (Denom.of_string (at 128))));
  is_error "129 characters" (Denom.of_string (at 129));
  is_error "the empty string" (Denom.of_string "")

let the_first_character_must_be_a_letter () =
  is_error "starting with a digit" (Denom.of_string "1uatom");
  is_error "starting with a slash" (Denom.of_string "/uatom");
  is_error "starting with a hyphen" (Denom.of_string "-uatom");
  (* ... but the rest of the string may hold all of those. *)
  Alcotest.(check string)
    "digits after the first" "au1"
    (Denom.to_string (ok (Denom.of_string "au1")));
  List.iter
    (fun c ->
      let d = Printf.sprintf "a%cb" c in
      Alcotest.(check string) d d (Denom.to_string (ok (Denom.of_string d))))
    [ '/'; ':'; '.'; '_'; '-' ]

let characters_outside_the_set () =
  List.iter
    (fun d -> is_error d (Denom.of_string d))
    [
      "uatom!";
      "uatom ";
      " uatom";
      "uat om";
      "uatom+";
      "uatom#";
      "uat\ttom";
      "uat\x00om";
      "uatóm";
    ]

let ibc_vouchers_are_flagged () =
  let voucher =
    ok
      (Denom.of_string
         "ibc/27394FB092D2ECCD56123C74F36E4C1F926001CEADA9CA97EA622B25F41E5EB2")
  in
  Alcotest.(check bool) "recognised" true (Denom.is_ibc_voucher voucher);
  Alcotest.(check bool)
    "uatom is not" false
    (Denom.is_ibc_voucher (ok (Denom.of_string "uatom")));
  (* "ibc" alone is a perfectly ordinary denomination, not a voucher. *)
  Alcotest.(check bool)
    "ibc alone is not" false
    (Denom.is_ibc_voucher (ok (Denom.of_string "ibc")))

let coins () =
  let c = ok (Coin.of_strings ~denom:"uatom" ~amount:"1000000") in
  Alcotest.(check string) "spelling" "1000000uatom" (Coin.to_string c);
  Alcotest.(check string) "amount" "1000000" (Amount.to_string (Coin.amount c));
  Alcotest.(check string) "denom" "uatom" (Denom.to_string (Coin.denom c));
  (* A zero coin is valid and does appear on the wire; Coin.Validate only
     rejects negative and nil. *)
  let z = ok (Coin.of_strings ~denom:"uatom" ~amount:"0") in
  Alcotest.(check bool) "zero is a coin" true (Coin.is_zero z);
  Alcotest.(check string) "and spells out" "0uatom" (Coin.to_string z);
  (* Both halves are validated. *)
  is_error "a bad denom" (Coin.of_strings ~denom:"1atom" ~amount:"1");
  is_error "a negative amount" (Coin.of_strings ~denom:"uatom" ~amount:"-1");
  is_error "a non-canonical amount"
    (Coin.of_strings ~denom:"uatom" ~amount:"01");
  (* Same number, different unit, is not the same coin. *)
  Alcotest.(check bool)
    "uatom is not uosmo" false
    (Coin.equal c (ok (Coin.of_strings ~denom:"uosmo" ~amount:"1000000")))

let an_eighteen_decimal_balance () =
  (* The case that rules out a 64-bit amount: a billion INJ in base units is
     10^27, which does not fit. *)
  let c =
    ok (Coin.of_strings ~denom:"inj" ~amount:"1000000000000000000000000000")
  in
  Alcotest.(check string)
    "carried exactly" "1000000000000000000000000000"
    (Amount.to_string (Coin.amount c))

let () =
  Alcotest.run "cosmos-coin"
    [
      ( "denom",
        [
          Alcotest.test_case "what the chains use" `Quick real_denominations;
          Alcotest.test_case "the length boundary" `Quick the_length_boundary;
          Alcotest.test_case "the first character" `Quick
            the_first_character_must_be_a_letter;
          Alcotest.test_case "characters outside the set" `Quick
            characters_outside_the_set;
          Alcotest.test_case "ibc vouchers are flagged" `Quick
            ibc_vouchers_are_flagged;
        ] );
      ( "coin",
        [
          Alcotest.test_case "construction and spelling" `Quick coins;
          Alcotest.test_case "an eighteen-decimal balance" `Quick
            an_eighteen_decimal_balance;
        ] );
    ]
