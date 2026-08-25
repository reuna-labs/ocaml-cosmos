(* secp256k1 keys, addresses and signatures.

   The vectors come from a pure-Python secp256k1 written for the purpose --
   point multiplication, RFC 6979, ECDSA, RIPEMD160(SHA256(pk)) and bech32 --
   which shares no code with this library. See
   conformance/oracle/secp256k1.py, and its README for how to regenerate.

   One of them is checkable against something older than either: private key 1
   derives hash160 751e76e8199196d454941c45d1b3a323f1433bd6, which is the
   witness program in BIP-173's own SegWit example
   (bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4). The Cosmos spelling below has
   the same bech32 data part and a different checksum, because the checksum
   covers the human-readable part. If the point multiplication, the
   compression, either hash or the bit conversion were wrong, that would not
   line up. *)

module Crypto = Cosmos_crypto
module Address = Cosmos_types.Address
module Prefix = Cosmos_types.Prefix

let ok = function
  | Ok v -> v
  | Error e -> Alcotest.failf "expected Ok, got Error %S" e

let is_error what = function
  | Error _ -> ()
  | Ok _ -> Alcotest.failf "expected %s to be rejected, it was accepted" what

let unhex h =
  String.init
    (String.length h / 2)
    (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2)))

let hex s =
  String.concat ""
    (List.map
       (fun c -> Printf.sprintf "%02x" (Char.code c))
       (List.init (String.length s) (String.get s)))

let key_vectors =
  [
    ( "0000000000000000000000000000000000000000000000000000000000000001",
      "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
      "751e76e8199196d454941c45d1b3a323f1433bd6",
      "cosmos1w508d6qejxtdg4y5r3zarvary0c5xw7k6ah60c" );
    ( "0000000000000000000000000000000000000000000000000000000000000002",
      "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
      "06afd46bcdfd22ef94ac122aa11f241244a37ecc",
      "cosmos1q6hag67dl53wl99vzg42z8eyzfz2xlkvsrxukv" );
    ( "0000000000000000000000000000000000000000000000000000000000000003",
      "02f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
      "7dd65592d0ab2fe0d0257d571abf032cd9db93dc",
      "cosmos10ht9tyks4vh7p5p904t340cr9nvahy7u8e84x9" );
    ( "0000000000000000000000000000000000000000000000000000000000c0ffee",
      "032a5bbcb0eede528e6abe5f2ec50ad7887eb5677af383a460b05ee23bf892dfe5",
      "f9981f750e294ebd1c1bf6b36d2d4f45e2a79070",
      "cosmos1lxvp7agw998t68qm76ek6t20gh320yrs39f96l" );
    ( "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140",
      "0379be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
      "adde4c73c7b9cee17da6c7b3e2b2eea1a0dcbe67",
      "cosmos14h0ycu78h88wzldxc7e79vhw5xsde0n8yvt9me" );
    ( "4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d",
      "03e68acfc0253a10620dff706b0a1b1f1f5833ea3beb3bde2250d5f271f3563606",
      "eac714fa0bf2f881a29b40688ee89d0c7c9298b6",
      "cosmos1atr3f7st7tugrg5mgp5ga6yap37f9x9kwn48zc" );
  ]

let signature_vectors =
  [
    ( "0000000000000000000000000000000000000000000000000000000000000001",
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "77c8d336572f6f466055b5f70f433851f8f535f6c4fc71133a6cfd71079d03b70ed9f5eb8aa5b266abac35d416c3207e7a538bf5f37649727d7a9823b1069577"
    );
    ( "0000000000000000000000000000000000000000000000000000000000000001",
      "4cbe19716b1aa73a67dc4b28c34391879b503259fc76852082b4dafcf0de85b2",
      "7e6bb707b051edb8a2540d82e7731e4f2e27a9c5920689d1adf2322ac70aafe40396987a6838ad2142ab688d8fabf238589af23c1b29fe08f063ae78cfaa4254"
    );
    ( "0000000000000000000000000000000000000000000000000000000000000001",
      "2c8dbd618dd6ae84dc847d48b7f10554a9b330671213be59b609ef512b9a80d9",
      "12bf97dfd7a189cc80160fcc84a54c489efb4982eafa7ad9d92c3b33efb647d77672a3ca5147985587bfedd66355f760867a43eb58a8235f9b393dbf33f9254d"
    );
    ( "0000000000000000000000000000000000000000000000000000000000000002",
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "a53ba0f56f12cc97761c3ca6606c976207f7c77739d992fbb30c8e894c6531962d684f62bdbe92bf49e5b58eef9a74b3643fa775c8f6ad5f233e8ccec00732b9"
    );
    ( "0000000000000000000000000000000000000000000000000000000000000002",
      "4cbe19716b1aa73a67dc4b28c34391879b503259fc76852082b4dafcf0de85b2",
      "7e46c017b3ed2427cbce0f9ea02ff97bb9b5747a4dfc401e49a3c8a2b469255e2840181a75acf74c5517ad8bc1c89d0a8c54647a02c595baaf4134356e45c650"
    );
    ( "0000000000000000000000000000000000000000000000000000000000000002",
      "2c8dbd618dd6ae84dc847d48b7f10554a9b330671213be59b609ef512b9a80d9",
      "177ff6df0907581981639756afd129c4faf960a5af2a9356f049a5462c6b7bdf51f150a254faae70cbb10f63840a7c11a66b2f994757819947684c3e7213b21d"
    );
    ( "0000000000000000000000000000000000000000000000000000000000000003",
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "34c5f82a78a2589566f1ed6cf22ab4c9e084c6c2d277fd8a554398b6166bc16d748678c9ed008d83a561b4732aa23f59541f34b9731588c862e79ea89809700f"
    );
    ( "0000000000000000000000000000000000000000000000000000000000000003",
      "4cbe19716b1aa73a67dc4b28c34391879b503259fc76852082b4dafcf0de85b2",
      "8a3091f07b14cabb95341660cfb1a2fbfe99673bcd9175ecd6afa7a5b34210324b84d2045b58c223ed12f8b78d22eac7ccf711ae3b77d477126e55cf39d05e52"
    );
    ( "0000000000000000000000000000000000000000000000000000000000000003",
      "2c8dbd618dd6ae84dc847d48b7f10554a9b330671213be59b609ef512b9a80d9",
      "fb56fd1a9377d292a0fb43d17df1c63b8e57ffaab186c28e4fb316cbd9c262906de882a3108310ffaa8e18d77ce97c228d7198c1460e5b2ae191f684aba9544e"
    );
    ( "0000000000000000000000000000000000000000000000000000000000c0ffee",
      "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "38b4d3f8c9de78f57412d6e7aeb56b7fe2f6520a8e0182c877d8928386c8c3124a8b14a6d9eb959571cd7a23d3221a4d478a572d695d1e3654c207d7848959bd"
    );
    ( "0000000000000000000000000000000000000000000000000000000000c0ffee",
      "4cbe19716b1aa73a67dc4b28c34391879b503259fc76852082b4dafcf0de85b2",
      "c6330ffd26dd46e2cfbf1e875b4be241636cb21296d0faa3fe289d29caae96c21fb4d6bd3ec405bf75476eacc9f00265ddb83e2892d829dd5c14c300cc086098"
    );
    ( "0000000000000000000000000000000000000000000000000000000000c0ffee",
      "2c8dbd618dd6ae84dc847d48b7f10554a9b330671213be59b609ef512b9a80d9",
      "54ca5567e5fad7bcbc46ecc8e245d57e83ae917ac7671ac67fc84628ebb25a043c38c2bfee236791f0de28373096d231e7a288469936337e5515ba4122a23019"
    );
  ]

let key = function k, _, _, _ -> unhex k
let priv v = ok (Crypto.private_key_of_bytes (key v))

let public_keys_match_the_oracle () =
  List.iter
    (fun ((k, expected, _, _) as v) ->
      let pk = Crypto.public_key_of_private (priv v) in
      Alcotest.(check string)
        ("compressed public key of " ^ k)
        expected
        (hex (Crypto.compressed pk)))
    key_vectors

let addresses_match_the_oracle () =
  List.iter
    (fun ((k, _, expected, _) as v) ->
      let pk = Crypto.public_key_of_private (priv v) in
      let a = Crypto.address_bytes pk in
      Alcotest.(check int) "twenty bytes" 20 (String.length a);
      Alcotest.(check string) ("address bytes of " ^ k) expected (hex a))
    key_vectors

let bech32_addresses_match_the_oracle () =
  (* The whole chain end to end: scalar to the string a human is shown. *)
  List.iter
    (fun ((k, _, _, expected) as v) ->
      let pk = Crypto.public_key_of_private (priv v) in
      let a = ok (Address.of_bytes Prefix.cosmos (Crypto.address_bytes pk)) in
      Alcotest.(check string)
        ("cosmos address of " ^ k) expected (Address.to_bech32 a))
    key_vectors

let signatures_match_the_oracle () =
  List.iter
    (fun (k, digest, expected) ->
      let key = ok (Crypto.private_key_of_bytes (unhex k)) in
      let sg = ok (Crypto.sign_digest ~key (unhex digest)) in
      Alcotest.(check string)
        ("signature over " ^ digest)
        expected
        (hex (Crypto.signature_to_bytes sg));
      (* and the oracle's own signature parses back as low-S *)
      Alcotest.(check bool)
        "the oracle's signature is low-S" true
        (Crypto.is_low_s (ok (Crypto.signature_of_bytes (unhex expected)))))
    signature_vectors

let every_signature_is_low_s () =
  (* The oracle normalises too, so agreeing with it does not by itself prove
     this. Signing many distinct digests does: without normalisation about half
     would come out high-S, and the SDK's verifier rejects those before it
     checks the mathematics. *)
  let key =
    ok
      (Crypto.private_key_of_bytes
         (unhex (List.nth key_vectors 5 |> fun (k, _, _, _) -> k)))
  in
  for i = 0 to 199 do
    let digest =
      Digestif.SHA256.(to_raw_string (digest_string (string_of_int i)))
    in
    let sg = ok (Crypto.sign_digest ~key digest) in
    if not (Crypto.is_low_s sg) then Alcotest.failf "signature %d is high-S" i
  done

let signing_is_deterministic () =
  (* RFC 6979: no randomness anywhere, so the same inputs give the same bytes.
     This is what makes a signature comparable against another
     implementation's, which the conformance fixtures depend on. *)
  let v = List.nth key_vectors 3 in
  let key = priv v in
  let digest =
    Digestif.SHA256.(to_raw_string (digest_string "sign me twice"))
  in
  let a = ok (Crypto.sign_digest ~key digest) in
  let b = ok (Crypto.sign_digest ~key digest) in
  Alcotest.(check string)
    "same bytes"
    (hex (Crypto.signature_to_bytes a))
    (hex (Crypto.signature_to_bytes b))

let sign_then_verify () =
  List.iter
    (fun v ->
      let key = priv v in
      let pk = Crypto.public_key_of_private key in
      let digest =
        Digestif.SHA256.(to_raw_string (digest_string "round trip"))
      in
      let sg = ok (Crypto.sign_digest ~key digest) in
      Alcotest.(check bool)
        "verifies" true
        (Crypto.verify_digest ~key:pk sg digest);
      (* a different message does not *)
      let other =
        Digestif.SHA256.(to_raw_string (digest_string "round tripp"))
      in
      Alcotest.(check bool)
        "not for another digest" false
        (Crypto.verify_digest ~key:pk sg other))
    key_vectors

let a_high_s_signature_is_refused () =
  (* Flip a valid signature to its malleable twin: (r, n - s) verifies against
     the curve and is exactly what the SDK rejects. n - s is computed here the
     way the library computes it internally, so the test is about the policy
     rather than about the arithmetic. *)
  let v = List.nth key_vectors 5 in
  let key = priv v in
  let pk = Crypto.public_key_of_private key in
  let digest = Digestif.SHA256.(to_raw_string (digest_string "malleable")) in
  let sg = ok (Crypto.sign_digest ~key digest) in
  let bytes = Crypto.signature_to_bytes sg in
  let r = String.sub bytes 0 32 and s = String.sub bytes 32 32 in
  let flipped = r ^ Mirage_crypto_ec.P256k1.Primitive.scalar_negate s in
  Alcotest.(check bool) "the twin is genuinely different" true (flipped <> bytes);
  is_error "a high-S signature" (Crypto.signature_of_bytes flipped);
  (* It can still be decoded deliberately, and shown to be malleable ... *)
  let any = ok (Crypto.signature_of_bytes_any flipped) in
  Alcotest.(check bool) "and is reported as high-S" false (Crypto.is_low_s any);
  (* ... but it does not verify, because the SDK would not accept it. *)
  Alcotest.(check bool)
    "and does not verify" false
    (Crypto.verify_digest ~key:pk any digest)

let malformed_inputs () =
  is_error "a 31-byte private key"
    (Crypto.private_key_of_bytes (String.make 31 '\x01'));
  is_error "a 33-byte private key"
    (Crypto.private_key_of_bytes (String.make 33 '\x01'));
  is_error "the zero private key"
    (Crypto.private_key_of_bytes (String.make 32 '\x00'));
  is_error "a private key equal to n"
    (Crypto.private_key_of_bytes
       (unhex "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"));
  is_error "an empty public key" (Crypto.public_key_of_bytes "");
  is_error "a truncated compressed point"
    (Crypto.public_key_of_bytes (unhex "0279be667ef9dcbbac"));
  is_error "a point not on the curve"
    (Crypto.public_key_of_bytes
       (unhex ("02" ^ String.concat "" (List.init 32 (fun _ -> "ff")))));
  is_error "a 63-byte signature"
    (Crypto.signature_of_bytes (String.make 63 '\x01'));
  is_error "a 65-byte signature"
    (Crypto.signature_of_bytes (String.make 65 '\x01'));
  let v = List.nth key_vectors 0 in
  is_error "a 31-byte digest"
    (Crypto.sign_digest ~key:(priv v) (String.make 31 '\x00'));
  is_error "a 33-byte digest"
    (Crypto.sign_digest ~key:(priv v) (String.make 33 '\x00'))

let compression_is_not_optional () =
  (* Hashing the uncompressed form gives a different address and no error,
     which is the quietest way to send funds nowhere. This pins the fact that
     address_bytes uses the compressed form. *)
  let v = List.nth key_vectors 5 in
  let pk = Crypto.public_key_of_private (priv v) in
  Alcotest.(check int)
    "compressed is 33 bytes" 33
    (String.length (Crypto.compressed pk));
  let uncompressed = Crypto.uncompressed pk in
  Alcotest.(check int) "uncompressed is 65" 65 (String.length uncompressed);
  let wrong =
    Digestif.RMD160.(
      to_raw_string
        (digest_string
           Digestif.SHA256.(to_raw_string (digest_string uncompressed))))
  in
  Alcotest.(check bool)
    "and hashes to something else entirely" false
    (String.equal wrong (Crypto.address_bytes pk))

let () =
  Alcotest.run "cosmos-crypto"
    [
      ( "against the oracle",
        [
          Alcotest.test_case "public keys" `Quick public_keys_match_the_oracle;
          Alcotest.test_case "address bytes" `Quick addresses_match_the_oracle;
          Alcotest.test_case "bech32 addresses" `Quick
            bech32_addresses_match_the_oracle;
          Alcotest.test_case "signatures" `Quick signatures_match_the_oracle;
        ] );
      ( "low-S",
        [
          Alcotest.test_case "every signature is low-S" `Slow
            every_signature_is_low_s;
          Alcotest.test_case "a high-S signature is refused" `Quick
            a_high_s_signature_is_refused;
        ] );
      ( "properties",
        [
          Alcotest.test_case "signing is deterministic" `Quick
            signing_is_deterministic;
          Alcotest.test_case "sign then verify" `Quick sign_then_verify;
          Alcotest.test_case "compression is not optional" `Quick
            compression_is_not_optional;
        ] );
      ("malformed", [ Alcotest.test_case "rejected" `Quick malformed_inputs ]);
    ]
