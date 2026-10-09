(** Native libsecp256k1 signing for Cosmos. Signatures cover an already hashed
    32-byte digest and encode r || s with low S. Verification enforces the
    Cosmos SDK low-S rule. Address derivation is RIPEMD160(SHA256(compressed
    pk)).

    Signing uses RFC6979 deterministic nonces. Public derivation and signing
    require an initialized Mirage RNG for independent context blinding;
    randomness does not change signatures. Applications provide entropy, and
    this library introduces no Unix or arbitrary-precision arithmetic
    dependency. *)

type private_key
type public_key

type signature
(** 64 bytes, [r] then [s], always low-S. *)

(** {2 Keys} *)

val private_key_of_bytes : string -> (private_key, string) result
(** 32 bytes, big-endian, and a scalar strictly between zero and the group
    order. Zero is a valid field element but not a valid key, and [n] itself is
    out of range. *)

val public_key_of_private : private_key -> public_key

val public_key_of_bytes : string -> (public_key, string) result
(** A SEC 1 point. Both the 33-byte compressed and 65-byte uncompressed forms
    parse, but only the compressed one appears in [SignerInfo] — see
    {!compressed}. *)

val compressed : public_key -> string
(** 33 bytes, SEC 1 compressed. This is the form that goes into
    [cosmos.crypto.secp256k1.PubKey] ([PubKeySize = 33]) and the form
    {!address_bytes} hashes. An uncompressed key derives a different address,
    which is a silent wrong answer rather than an error. *)

val uncompressed : public_key -> string
(** 65 bytes, SEC 1 uncompressed.

    Present so that a caller displaying a key can, and so that the difference is
    testable — not because anything in the Cosmos protocol uses it.
    {!address_bytes} hashes the {!compressed} form; hashing this one produces a
    different, wrong address and no error at all. *)

(** {2 Addresses} *)

val address_bytes : public_key -> string
(** [RIPEMD160(SHA256(compressed pk))], 20 bytes — the Bitcoin construction, as
    [PubKey.Address()] documents and implements
    ([crypto/keys/secp256k1/secp256k1.go:156-166]). *)

(** {2 Signing} *)

val sign_digest : key:private_key -> string -> (signature, string) result
(** [sign_digest ~key digest] signs 32 bytes already computed, and normalises
    the result to low-S. *)

val verify_digest : key:public_key -> signature -> string -> bool
(** Verification of a high-S signature is [false], matching the SDK rather than
    the curve. *)

val is_low_s : signature -> bool

val signature_to_bytes : signature -> string
(** 64 bytes, [r ‖ s]. *)

val signature_of_bytes : string -> (signature, string) result
(** Rejects a high-S signature, as [signatureFromBytes] does. A caller that
    wants to look at one anyway wants {!signature_of_bytes_any}. *)

val signature_of_bytes_any : string -> (signature, string) result
(** Parses without the low-S check, so that a malleable signature can be decoded
    and shown to be malleable. {!verify_digest} still refuses it. *)
