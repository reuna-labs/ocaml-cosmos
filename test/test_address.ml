(* Addresses and prefixes.

   The bech32 vectors are the SDK's own literals, lifted from
   types/address_test.go and types/bech32/bech32_test.go at the pinned
   revision -- not generated here. A fixture this library produced would only
   record that it agrees with itself. See docs/protocol-pin.md. *)

module Prefix = Cosmos_types.Prefix
module Address = Cosmos_types.Address

let ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "expected Ok, got Error %S" e

let is_error what = function
  | Error _ -> ()
  | Ok _ -> Alcotest.failf "expected %s to be rejected, it was accepted" what

let bytes_of_hex h =
  String.init
    (String.length h / 2)
    (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2)))

(* --- the SDK's vectors ------------------------------------------------- *)

let ten = bytes_of_hex "00010203040506070809"
let twenty = bytes_of_hex "000102030405060708090a0b0c0d0e0f10111213"

let sdk_vectors =
  [
    ("cosmos1qqqsyqcyq5rqwzqfys8f67", "cosmos", Prefix.Account, ten);
    ("prefixa1qqqsyqcyq5rqwzqf3953cc", "prefixa", Prefix.Account, ten);
    ("prefixb1qqqsyqcyq5rqwzqf20xxpc", "prefixb", Prefix.Account, ten);
    ( "prefixa1qqqsyqcyq5rqwzqfpg9scrgwpugpzysn7hzdtn",
      "prefixa",
      Prefix.Account,
      twenty );
    ( "prefixb1qqqsyqcyq5rqwzqfpg9scrgwpugpzysnrujsuw",
      "prefixb",
      Prefix.Account,
      twenty );
  ]

let decodes_the_sdk_vectors () =
  List.iter
    (fun (s, base, kind, expected) ->
      let a = ok (Address.of_bech32 ~base s) in
      Alcotest.(check string) (s ^ ": bytes") expected (Address.to_bytes a);
      Alcotest.(check bool)
        (s ^ ": kind") true
        (Prefix.kind (Address.prefix a) = kind))
    sdk_vectors

let encodes_the_sdk_vectors () =
  List.iter
    (fun (s, base, kind, bytes) ->
      let p = ok (Prefix.make ~base kind) in
      let a = ok (Address.of_bytes p bytes) in
      Alcotest.(check string) "round trip" s (Address.to_bech32 a))
    sdk_vectors

(* --- the hazard this type exists for ----------------------------------- *)

let one_key_three_spellings () =
  let mk kind =
    ok (Address.of_bytes (ok (Prefix.make ~base:"cosmos" kind)) twenty)
  in
  let acc = mk Prefix.Account
  and valoper = mk Prefix.Validator
  and valcons = mk Prefix.Consensus in
  (* The strings differ ... *)
  let strings = List.map Address.to_bech32 [ acc; valoper; valcons ] in
  Alcotest.(check bool)
    "three distinct spellings" true
    (List.length (List.sort_uniq String.compare strings) = 3);
  List.iter2
    (fun expected got ->
      Alcotest.(check bool)
        ("starts with " ^ expected)
        true
        (String.length got > String.length expected
        && String.sub got 0 (String.length expected) = expected))
    [ "cosmos1"; "cosmosvaloper1"; "cosmosvalcons1" ]
    strings;
  (* ... the bytes do not, and that is the whole problem. *)
  Alcotest.(check bool) "same bytes" true (Address.same_bytes acc valoper);
  Alcotest.(check bool) "not equal" false (Address.equal acc valoper)

let a_validator_address_is_not_an_account () =
  (* Decoding tells you which of the three you were handed, so a caller that
     wanted an account can refuse a validator rather than transferring to it. *)
  let valoper =
    Address.to_bech32
      (ok
         (Address.of_bytes
            (ok (Prefix.make ~base:"cosmos" Prefix.Validator))
            twenty))
  in
  let decoded = ok (Address.of_bech32 ~base:"cosmos" valoper) in
  Alcotest.(check bool)
    "recognised as a validator address" true
    (Prefix.kind (Address.prefix decoded) = Prefix.Validator)

let another_chains_address_is_refused () =
  (* The reason of_bech32 takes ~base: a Cosmos Hub address pasted where an
     Osmosis one belongs decodes perfectly well as bech32. *)
  let hub = List.hd sdk_vectors |> fun (s, _, _, _) -> s in
  is_error "a cosmos address decoded as osmo"
    (Address.of_bech32 ~base:"osmo" hub)

(* --- what the chain accepts, and what it does not ---------------------- *)

let length_follows_the_sdk_not_the_convention () =
  let p = Prefix.cosmos in
  (* Ten bytes is not a conventional address and the SDK round-trips it. *)
  let short = ok (Address.of_bytes p ten) in
  Alcotest.(check int) "ten bytes is accepted" 10 (Address.length short);
  Alcotest.(check bool)
    "but not standard length" false
    (Address.is_standard_length short);
  Alcotest.(check bool)
    "twenty is" true
    (Address.is_standard_length (ok (Address.of_bytes p twenty)));
  Alcotest.(check bool)
    "thirty-two is" true
    (Address.is_standard_length
       (ok (Address.of_bytes p (String.make 32 '\x00'))));
  (* The only two rules the SDK actually enforces. *)
  is_error "an empty address" (Address.of_bytes p "");
  is_error "a 256-byte address" (Address.of_bytes p (String.make 256 '\x00'));
  Alcotest.(check int)
    "255 is the limit, and is allowed" 255
    (Address.length (ok (Address.of_bytes p (String.make 255 '\x00'))))

let bech32m_is_refused () =
  (* Built with the same bytes and hrp but the other checksum constant. The
     SDK calls btcutil's bech32.Decode, which is BIP-173 only. *)
  let groups = List.init 20 (fun i -> i) in
  let data =
    match Web3_codec_bech32.convertbits ~pad:true groups ~from:8 ~into:5 with
    | Some d -> d
    | None -> Alcotest.fail "bit conversion"
  in
  let m =
    Web3_codec_bech32.encode ~max_length:1023 Web3_codec_bech32.Bech32m
      ~hrp:"cosmos" ~data
  in
  is_error "a bech32m checksum" (Address.of_bech32 ~base:"cosmos" m)

let long_addresses_are_not_capped_at_ninety () =
  (* BIP-173 caps a bech32 string at 90 characters; the SDK passes 1023. A
     255-byte address spells out to well over 90, and the chain takes it. *)
  let a = ok (Address.of_bytes Prefix.cosmos (String.make 255 '\x2a')) in
  let s = Address.to_bech32 a in
  Alcotest.(check bool)
    (Printf.sprintf "%d characters, past BIP-173's 90" (String.length s))
    true
    (String.length s > 90);
  let back = ok (Address.of_bech32 ~base:"cosmos" s) in
  Alcotest.(check string)
    "and round trips" (Address.to_bytes a) (Address.to_bytes back)

(* --- prefixes ---------------------------------------------------------- *)

let prefix_construction () =
  Alcotest.(check string)
    "account" "cosmos"
    (Prefix.to_string (ok (Prefix.make ~base:"cosmos" Prefix.Account)));
  Alcotest.(check string)
    "validator" "cosmosvaloper"
    (Prefix.to_string (ok (Prefix.make ~base:"cosmos" Prefix.Validator)));
  Alcotest.(check string)
    "consensus" "cosmosvalcons"
    (Prefix.to_string (ok (Prefix.make ~base:"cosmos" Prefix.Consensus)));
  Alcotest.(check string)
    "base survives" "cosmos"
    (Prefix.base (ok (Prefix.make ~base:"cosmos" Prefix.Consensus)));
  (* Real chains, to make sure nothing is special-cased about "cosmos". *)
  List.iter
    (fun base ->
      Alcotest.(check string)
        (base ^ " validator") (base ^ "valoper")
        (Prefix.to_string (ok (Prefix.make ~base Prefix.Validator))))
    [ "osmo"; "celestia"; "inj"; "dydx"; "neutron"; "noble" ]

let malformed_prefixes_are_refused () =
  is_error "an empty base" (Prefix.make ~base:"" Prefix.Account);
  is_error "an upper-case base" (Prefix.make ~base:"Cosmos" Prefix.Account);
  is_error "a base with a hyphen" (Prefix.make ~base:"cos-mos" Prefix.Account);
  is_error "a base of 78 characters"
    (Prefix.make ~base:(String.make 78 'a') Prefix.Account);
  (* This one is subtler: a chain whose account prefix ended in valoper could
     not be told apart from another chain's validator addresses. *)
  is_error "a base ending in valoper"
    (Prefix.make ~base:"cosmosvaloper" Prefix.Account);
  is_error "a base ending in valcons"
    (Prefix.make ~base:"cosmosvalcons" Prefix.Account)

let of_hrp_is_exact () =
  Alcotest.(check bool)
    "cosmosvaloper is the validator prefix of cosmos" true
    (Prefix.kind (ok (Prefix.of_hrp ~base:"cosmos" "cosmosvaloper"))
    = Prefix.Validator);
  is_error "an unrelated hrp" (Prefix.of_hrp ~base:"cosmos" "osmo");
  is_error "a near miss" (Prefix.of_hrp ~base:"cosmos" "cosmosvalope")

let () =
  Alcotest.run "cosmos-types"
    [
      ( "sdk vectors",
        [
          Alcotest.test_case "decode" `Quick decodes_the_sdk_vectors;
          Alcotest.test_case "encode" `Quick encodes_the_sdk_vectors;
        ] );
      ( "prefix confusion",
        [
          Alcotest.test_case "one key, three spellings" `Quick
            one_key_three_spellings;
          Alcotest.test_case "a validator address says so" `Quick
            a_validator_address_is_not_an_account;
          Alcotest.test_case "another chain's address is refused" `Quick
            another_chains_address_is_refused;
        ] );
      ( "length and encoding",
        [
          Alcotest.test_case "the SDK's rules, not the convention" `Quick
            length_follows_the_sdk_not_the_convention;
          Alcotest.test_case "bech32m is refused" `Quick bech32m_is_refused;
          Alcotest.test_case "past BIP-173's 90 characters" `Quick
            long_addresses_are_not_capped_at_ninety;
        ] );
      ( "prefix",
        [
          Alcotest.test_case "construction" `Quick prefix_construction;
          Alcotest.test_case "malformed bases are refused" `Quick
            malformed_prefixes_are_refused;
          Alcotest.test_case "of_hrp is exact" `Quick of_hrp_is_exact;
        ] );
    ]
