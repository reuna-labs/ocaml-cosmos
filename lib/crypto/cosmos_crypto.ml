(* Fiat-crypto, constant time. This is the only backend a private key reaches,
   and there is deliberately no second one: Tron needs a reference
   implementation for public-key recovery, and recovery is exactly what Cosmos
   does not do. See dune. *)
module Dsa = Mirage_crypto_ec.P256k1.Dsa
module Prim = Mirage_crypto_ec.P256k1.Primitive

type private_key = Dsa.priv
type public_key = Dsa.pub
type signature = { r : string; s : string }

let scalar_length = 32
let digest_length = 32
let signature_length = 64

(* n/2 for secp256k1, big-endian. A fixed-width big-endian comparison is a
   numeric one, so this needs no arithmetic to use.

   n = FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFE BAAEDCE6 AF48A03B BFD25E8C D0364141 *)
let half_order =
  "\x7f\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\x5d\x57\x6e\x73\x57\xa4\x50\x1d\xdf\xe9\x2f\x46\x68\x1b\x20\xa0"

let is_over_half_order s = String.compare s half_order > 0

(* Keys *)

let private_key_of_bytes b =
  if String.length b <> scalar_length then
    Error
      (Printf.sprintf "crypto: a private key is %d bytes, got %d" scalar_length
         (String.length b))
  else
    match Dsa.priv_of_octets b with
    | Ok k -> Ok k
    | Error _ -> Error "crypto: private key is not in [1, n)"
    | exception _ -> Error "crypto: private key is not in [1, n)"

let public_key_of_private = Dsa.pub_of_priv

let public_key_of_bytes b =
  (* pub_of_octets returns a result and also raises: a short buffer announcing
     a compressed point sends decompression past the end and String.sub raises.
     Public keys arrive from the wire and this function promises a result, so
     the promise is kept here rather than assumed. ocaml-tron found this by
     fuzzing; the same runtime is underneath. *)
  match Dsa.pub_of_octets b with
  | Ok k -> Ok k
  | Error _ -> Error "crypto: not a secp256k1 point"
  | exception _ -> Error "crypto: not a secp256k1 point"

let compressed k = Dsa.pub_to_octets ~compress:true k
let uncompressed k = Dsa.pub_to_octets ~compress:false k

let address_bytes k =
  (* crypto/keys/secp256k1/secp256k1.go:156-166 -- RIPEMD160(SHA256(pubkey)),
     over the 33-byte compressed form. Hashing the uncompressed form produces a
     different address and no error. *)
  let sha = Digestif.SHA256.(to_raw_string (digest_string (compressed k))) in
  Digestif.RMD160.(to_raw_string (digest_string sha))

(* Signing *)

let normalise { r; s } =
  (* scalar_negate is (n - s) mod n, constant time, and needs no bignum -- the
     alternative is arbitrary-precision arithmetic on a value derived from the
     nonce, which is where a timing leak gets reintroduced by hand. *)
  if is_over_half_order s then { r; s = Prim.scalar_negate s } else { r; s }

let sign_digest ~key digest =
  if String.length digest <> digest_length then
    Error
      (Printf.sprintf "crypto: a digest is %d bytes, got %d" digest_length
         (String.length digest))
  else
    match Dsa.sign ~key digest with
    | r, s -> Ok (normalise { r; s })
    | exception Mirage_crypto_ec.Message_too_long ->
        Error "crypto: digest is longer than the group order"
    | exception Invalid_argument m -> Error ("crypto: " ^ m)

let is_low_s { s; _ } = not (is_over_half_order s)

let verify_digest ~key sg digest =
  (* The SDK's verifier rejects a high-S signature before it checks the
     mathematics (secp256k1_nocgo.go:43-51), so this refuses it too. Verifying
     against the curve alone would accept signatures a node will not. *)
  is_low_s sg && Dsa.verify ~key (sg.r, sg.s) digest

let signature_to_bytes { r; s } = r ^ s

let parse b =
  if String.length b <> signature_length then
    Error
      (Printf.sprintf "crypto: a signature is %d bytes, got %d" signature_length
         (String.length b))
  else
    let r = String.sub b 0 scalar_length
    and s = String.sub b scalar_length scalar_length in
    Ok { r; s }

let signature_of_bytes b =
  match parse b with
  | Error _ as e -> e
  | Ok sg ->
      if is_low_s sg then Ok sg
      else
        Error
          "crypto: signature is not in lower-S form, and is therefore malleable"

let signature_of_bytes_any = parse
