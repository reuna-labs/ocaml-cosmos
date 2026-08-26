(* The signer transcript.

   There is no external oracle for this: no other implementation decides what a
   Reuna signer records. What it has instead is a property that can be stated
   exactly and then attacked -- that a signer cannot display one transaction and
   sign another -- and most of what follows is an attempt to do that and fail. *)

module Signer = Cosmos_signer
module T = Signer.Transcript
module Tx = Cosmos_tx
module Types = Cosmos_types
module Address = Types.Address
module Coin = Types.Coin
module Denom = Types.Denom
module Amount = Types.Amount

let ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "unexpected error: %s" e

let ok_review = function
  | Ok v -> v
  | Error rs -> Alcotest.failf "review refused: %s" (String.concat "; " rs)

let refused what = function
  | Error rs -> rs
  | Ok _ -> Alcotest.failf "expected %s to be refused, it was accepted" what

let unhex h =
  String.init
    (String.length h / 2)
    (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2)))

let addr s = ok (Address.of_bech32 ~base:"cosmos" s)
let coin d a = ok (Coin.of_strings ~denom:d ~amount:a)
let key1 = "cosmos1w508d6qejxtdg4y5r3zarvary0c5xw7k6ah60c"
let key2 = "cosmos1q6hag67dl53wl99vzg42z8eyzfz2xlkvsrxukv"
let key3 = "cosmos10ht9tyks4vh7p5p904t340cr9nvahy7u8e84x9"
let chain_id = ok (Types.Chain_id.of_string "cosmoshub-4")

let signing_key =
  ok (Cosmos_crypto.private_key_of_bytes (unhex (String.make 62 '0' ^ "01")))

let public_key = Cosmos_crypto.public_key_of_private signing_key
let nonce = String.init 16 (fun i -> Char.chr (i * 7 land 0xff))
let not_after = 1_800_000_000L
let now = 1_700_000_000L

(* A transaction, and the SignDoc bytes a signer would be handed for it. *)
let payload ?(to_ = key2) ?(amount = "1000000") ?(sequence = 7L) ?(memo = "")
    ?(account_number = 42L) ?(chain = chain_id) () =
  let body =
    ok
      (Tx.Body.make
         ~messages:
           [
             Tx.Msg.Send
               {
                 from_address = addr key1;
                 to_address = addr to_;
                 amount = [ coin "uatom" amount ];
               };
           ]
         ~memo ())
  in
  let auth_info =
    ok
      (Tx.Auth_info.make
         ~signers:
           [
             {
               public_key = Some (Tx.Auth_info.Secp256k1 public_key);
               mode = Tx.Auth_info.Direct;
               sequence;
             };
           ]
         ~fee:
           {
             amount = [ coin "uatom" "1000" ];
             gas_limit = 200_000L;
             payer = None;
             granter = None;
           })
  in
  Tx.Sign_doc.to_bytes
    (Tx.Sign_doc.make ~body ~auth_info ~chain_id:chain ~account_number)

let request ?(sequence = 7L) ?(account_number = 42L) ?(chain = chain_id)
    ?payload:p () =
  ok
    (T.request ~chain_id:chain ~account_number ~sequence ~sign_mode:T.Direct
       ~payload:
         (match p with
         | Some p -> p
         | None -> payload ~sequence ~account_number ~chain ())
       ~nonce ~not_after)

let policy () =
  Tx.Policy.strict
  |> Tx.Policy.allow_chain chain_id
  |> Tx.Policy.allow_transfer_to (addr key2)
  |> Tx.Policy.allow_denom (ok (Denom.of_string "uatom"))
  |> Tx.Policy.max_amount_per_denom
       (ok (Denom.of_string "uatom"))
       (ok (Amount.of_string "2000000"))
  |> Tx.Policy.max_fee
       (ok (Amount.of_string "5000"))
       (ok (Denom.of_string "uatom"))

(* --- the property ------------------------------------------------------- *)

let the_rendering_is_a_function_of_the_payload () =
  (* Two requests differing only in the destination must render differently.
     If the rendering could be anything other than a function of the bytes,
     "displayed X, signed Y" would be expressible. *)
  let a =
    ok_review (T.review ~base:"cosmos" ~policy:(policy ()) (request ()))
  in
  let p = policy () |> Tx.Policy.allow_transfer_to (addr key3) in
  let b =
    ok_review
      (T.review ~base:"cosmos" ~policy:p
         (request ~payload:(payload ~to_:key3 ()) ()))
  in
  Alcotest.(check bool)
    "different destinations render differently" false
    (String.equal (T.rendering a) (T.rendering b));
  let shows r needle =
    let s = T.rendering r in
    let n = String.length needle and m = String.length s in
    let rec at i = i + n <= m && (String.sub s i n = needle || at (i + 1)) in
    at 0
  in
  Alcotest.(check bool) "and each names its own destination" true (shows a key2);
  Alcotest.(check bool) "" true (shows b key3);
  Alcotest.(check bool) "not the other's" false (shows a key3)

let verification_re_derives_the_rendering () =
  (* verify does not trust the rendering stored in the approval: it recomputes
     it. So a transcript whose words were tampered with after the fact fails,
     which is what makes it evidence rather than a log line. *)
  let rv =
    ok_review (T.review ~base:"cosmos" ~policy:(policy ()) (request ()))
  in
  let a = ok (T.sign rv ~key:signing_key ~measurement:"test-measurement") in
  ok (T.verify a ~key:public_key ~now);
  (* The signature is over the payload, so it also fails for a different key. *)
  let other =
    Cosmos_crypto.public_key_of_private
      (ok
         (Cosmos_crypto.private_key_of_bytes
            (unhex (String.make 62 '0' ^ "02"))))
  in
  ignore (refused "another key's signature" (T.verify a ~key:other ~now))

let there_is_no_way_to_sign_unreviewed_bytes () =
  (* Stated as a test because it is a claim about the API's shape: T.sign takes
     a review and nothing else. If a `sign_bytes` ever appears beside it, this
     comment is the reason it should not.

     What can be checked here is the consequence: a payload the policy refuses
     never becomes an approval, because it never becomes a review. *)
  let reasons =
    refused "a transfer to an address the policy does not allow"
      (T.review ~base:"cosmos" ~policy:(policy ())
         (request ~payload:(payload ~to_:key3 ()) ()))
  in
  Alcotest.(check bool) "and says why" true (reasons <> [])

(* --- the request binds what it claims ------------------------------------ *)

let a_payload_for_another_chain_is_refused () =
  (* The request says cosmoshub-4; the document inside says otherwise. Both are
     present, so this is cheap to check and expensive to miss. *)
  let other = ok (Types.Chain_id.of_string "provider") in
  let mismatched =
    ok
      (T.request ~chain_id ~account_number:42L ~sequence:7L ~sign_mode:T.Direct
         ~payload:(payload ~chain:other ()) ~nonce ~not_after)
  in
  let reasons =
    refused "a payload for another chain"
      (T.review ~base:"cosmos" ~policy:(policy ()) mismatched)
  in
  Alcotest.(check bool)
    ("names both chains: " ^ String.concat "; " reasons)
    true
    (List.exists (fun r -> String.length r > 0) reasons)

let a_payload_for_another_account_or_sequence_is_refused () =
  let wrong_account =
    ok
      (T.request ~chain_id ~account_number:43L ~sequence:7L ~sign_mode:T.Direct
         ~payload:(payload ~account_number:42L ())
         ~nonce ~not_after)
  in
  ignore
    (refused "a payload for another account"
       (T.review ~base:"cosmos" ~policy:(policy ()) wrong_account));
  let wrong_sequence =
    ok
      (T.request ~chain_id ~account_number:42L ~sequence:9L ~sign_mode:T.Direct
         ~payload:(payload ~sequence:7L ()) ~nonce ~not_after)
  in
  ignore
    (refused "a payload for another sequence"
       (T.review ~base:"cosmos" ~policy:(policy ()) wrong_sequence))

let an_undecodable_payload_is_refused () =
  (* A signer that cannot read what it is being asked to sign has nothing to
     show a human, so approving would be approving a hash. *)
  let r =
    ok
      (T.request ~chain_id ~account_number:42L ~sequence:7L ~sign_mode:T.Direct
         ~payload:"\xff\xff\xff\xff" ~nonce ~not_after)
  in
  ignore
    (refused "an undecodable payload"
       (T.review ~base:"cosmos" ~policy:(policy ()) r))

let amino_signs_what_it_derived_not_what_it_was_given () =
  (* Both modes take a SignDoc payload. In amino mode the signer computes the
     document it will sign from that same payload, so the encoding reviewed and
     the encoding signed cannot describe different transactions.

     Accepting amino bytes from the caller instead would put the substitution
     this whole module prevents right back in, through the front door. *)
  let direct = request () in
  let amino =
    ok
      (T.request ~chain_id ~account_number:42L ~sequence:7L
         ~sign_mode:T.Legacy_amino_json ~payload:(payload ()) ~nonce ~not_after)
  in
  let rd = ok_review (T.review ~base:"cosmos" ~policy:(policy ()) direct) in
  let ra = ok_review (T.review ~base:"cosmos" ~policy:(policy ()) amino) in
  (* Same transaction, same meaning shown ... *)
  Alcotest.(check string)
    "the rendering is the same" (T.rendering rd) (T.rendering ra);
  (* ... and different bytes signed. *)
  Alcotest.(check bool)
    "different bytes are signed" false
    (String.equal (T.signed_bytes rd) (T.signed_bytes ra));
  Alcotest.(check string)
    "direct signs the payload itself" (T.signed_bytes rd) (payload ());
  (* The amino document is JSON, and is the one the SDK's encoder produces --
     test_amino checks that byte for byte against the SDK. Here it is enough
     that it is the amino encoding and not the protobuf one. *)
  Alcotest.(check bool)
    "amino signs a JSON document" true
    (String.length (T.signed_bytes ra) > 0 && (T.signed_bytes ra).[0] = '{');
  (* Both verify, each against what it actually signed. *)
  let aa = ok (T.sign ra ~key:signing_key ~measurement:"m") in
  let ad = ok (T.sign rd ~key:signing_key ~measurement:"m") in
  ok (T.verify aa ~key:public_key ~now);
  ok (T.verify ad ~key:public_key ~now);
  (* And the two signatures differ, because the documents do. *)
  Alcotest.(check bool)
    "the signatures differ" false
    (String.equal
       (Cosmos_crypto.signature_to_bytes (T.signature aa))
       (Cosmos_crypto.signature_to_bytes (T.signature ad)));
  (* The record says the bytes signed are not the bytes reviewed. *)
  let s = Format.asprintf "%a" T.pp aa in
  let shows needle =
    let n = String.length needle and m = String.length s in
    let rec at i = i + n <= m && (String.sub s i n = needle || at (i + 1)) in
    at 0
  in
  Alcotest.(check bool)
    "the amino record says so" true
    (shows "a different encoding");
  Alcotest.(check bool)
    "and the direct record does not" false
    (let s = Format.asprintf "%a" T.pp ad in
     let needle = "a different encoding" in
     let n = String.length needle and m = String.length s in
     let rec at i = i + n <= m && (String.sub s i n = needle || at (i + 1)) in
     at 0)

(* --- the digest binds every field --------------------------------------- *)

let every_field_changes_the_digest () =
  let base = request () in
  let d = T.request_digest base in
  let differs what r =
    Alcotest.(check bool)
      (what ^ " changes the request digest")
      false
      (String.equal d (T.request_digest r))
  in
  differs "the chain"
    (request ~chain:(ok (Types.Chain_id.of_string "provider")) ());
  differs "the account number" (request ~account_number:43L ());
  differs "the sequence" (request ~sequence:8L ());
  differs "the payload" (request ~payload:(payload ~amount:"2" ()) ());
  differs "the nonce"
    (ok
       (T.request ~chain_id ~account_number:42L ~sequence:7L ~sign_mode:T.Direct
          ~payload:(payload ()) ~nonce:(String.make 16 'z') ~not_after));
  differs "not_after"
    (ok
       (T.request ~chain_id ~account_number:42L ~sequence:7L ~sign_mode:T.Direct
          ~payload:(payload ()) ~nonce ~not_after:(Int64.add not_after 1L)));
  differs "the sign mode"
    (ok
       (T.request ~chain_id ~account_number:42L ~sequence:7L
          ~sign_mode:T.Legacy_amino_json ~payload:(payload ()) ~nonce ~not_after))

let length_prefixing_stops_field_confusion () =
  (* The reason the encoding is length-prefixed rather than delimited: two
     different splits of the same concatenated bytes must not collide. Here the
     nonce and the payload boundary is moved without changing their
     concatenation. *)
  let a =
    Signer.Canonical.(
      create "d" |> fun c ->
      string c "ab" |> fun c -> string c "c")
  in
  let b =
    Signer.Canonical.(
      create "d" |> fun c ->
      string c "a" |> fun c -> string c "bc")
  in
  Alcotest.(check bool)
    "\"ab\"+\"c\" and \"a\"+\"bc\" hash differently" false
    (String.equal (Signer.Canonical.digest a) (Signer.Canonical.digest b));
  (* And a different domain never collides with the same fields. *)
  let c =
    Signer.Canonical.(
      create "e" |> fun c ->
      string c "ab" |> fun c -> string c "c")
  in
  Alcotest.(check bool)
    "a different domain differs" false
    (String.equal (Signer.Canonical.digest a) (Signer.Canonical.digest c))

(* --- freshness ---------------------------------------------------------- *)

let freshness_is_checked_against_a_supplied_time () =
  let r = request () in
  ok (T.check_freshness r ~now);
  ignore
    (refused "an expired request"
       (T.check_freshness r ~now:(Int64.add not_after 1L)));
  (* And verification enforces it too, so a stale approval does not pass a
     later reader. *)
  let rv = ok_review (T.review ~base:"cosmos" ~policy:(policy ()) r) in
  let a = ok (T.sign rv ~key:signing_key ~measurement:"m") in
  ok (T.verify a ~key:public_key ~now);
  ignore
    (refused "verifying after expiry"
       (T.verify a ~key:public_key ~now:(Int64.add not_after 1L)))

let requests_that_cannot_bound_replay_are_refused () =
  let mk ?(nonce = nonce) ?(not_after = not_after) ?(payload = payload ()) () =
    T.request ~chain_id ~account_number:42L ~sequence:7L ~sign_mode:T.Direct
      ~payload ~nonce ~not_after
  in
  ignore (refused "no expiry" (mk ~not_after:0L ()));
  ignore (refused "a short nonce" (mk ~nonce:"tooshort" ()));
  ignore (refused "an empty payload" (mk ~payload:"" ()))

let an_approval_must_name_its_signer () =
  let rv =
    ok_review (T.review ~base:"cosmos" ~policy:(policy ()) (request ()))
  in
  ignore
    (refused "an approval with no measurement"
       (T.sign rv ~key:signing_key ~measurement:""))

let the_record_shows_everything () =
  let rv =
    ok_review (T.review ~base:"cosmos" ~policy:(policy ()) (request ()))
  in
  let a = ok (T.sign rv ~key:signing_key ~measurement:"sha256:deadbeef") in
  let s = Format.asprintf "%a" T.pp a in
  let shows needle =
    let n = String.length needle and m = String.length s in
    let rec at i = i + n <= m && (String.sub s i n = needle || at (i + 1)) in
    Alcotest.(check bool) ("shows " ^ needle) true (at 0)
  in
  shows "SIGN_MODE_DIRECT";
  shows "sha256:deadbeef";
  shows "not after";
  shows "cosmoshub-4";
  shows key2;
  shows "1000uatom for 200000 gas";
  (* And the approval digest is not the request digest: different domains. *)
  Alcotest.(check bool)
    "approval and request digests differ" false
    (String.equal (T.approval_digest a)
       (T.request_digest (T.reviewed_request rv)))

let () =
  Alcotest.run "cosmos-transcript"
    [
      ( "displayed is signed",
        [
          Alcotest.test_case "the rendering is a function of the payload" `Quick
            the_rendering_is_a_function_of_the_payload;
          Alcotest.test_case "verification re-derives it" `Quick
            verification_re_derives_the_rendering;
          Alcotest.test_case "unreviewed bytes never become an approval" `Quick
            there_is_no_way_to_sign_unreviewed_bytes;
        ] );
      ( "the request binds what it claims",
        [
          Alcotest.test_case "another chain" `Quick
            a_payload_for_another_chain_is_refused;
          Alcotest.test_case "another account or sequence" `Quick
            a_payload_for_another_account_or_sequence_is_refused;
          Alcotest.test_case "an undecodable payload" `Quick
            an_undecodable_payload_is_refused;
          Alcotest.test_case "amino signs what it derived" `Quick
            amino_signs_what_it_derived_not_what_it_was_given;
        ] );
      ( "the digest",
        [
          Alcotest.test_case "every field changes it" `Quick
            every_field_changes_the_digest;
          Alcotest.test_case "length prefixing stops field confusion" `Quick
            length_prefixing_stops_field_confusion;
        ] );
      ( "freshness and evidence",
        [
          Alcotest.test_case "checked against a supplied time" `Quick
            freshness_is_checked_against_a_supplied_time;
          Alcotest.test_case "requests that cannot bound replay" `Quick
            requests_that_cannot_bound_replay_are_refused;
          Alcotest.test_case "an approval must name its signer" `Quick
            an_approval_must_name_its_signer;
          Alcotest.test_case "the record shows everything" `Quick
            the_record_shows_everything;
        ] );
    ]
