(** secp256k1 signing and address derivation for Cosmos SDK chains.

    {2 One hash, and the signature is not recoverable}

    A Cosmos signature covers [SHA-256] of the serialized [SignDoc] and goes on
    the wire as 64 bytes, [r] then [s]
    ([crypto/keys/secp256k1/secp256k1_nocgo.go:13-21] at the pinned revision).
    There is no recovery byte and no recovery function here: the public key
    travels in [SignerInfo], so nothing ever needs to derive it from a
    signature. That is what keeps the reference bignum backend — and with it
    zarith and GMP — out of this closure.

    Nothing here hashes a message. {!sign_digest} takes 32 bytes already
    computed, because the caller is the only party that knows what went into
    them.

    {2 Low-S is a requirement, not a nicety}

    The SDK rejects a signature whose [s] is above [n/2] as malleable — its
    verifier calls [signatureFromBytes], which returns an error for
    [s.IsOverHalfOrder()] before it checks anything else
    ([secp256k1_nocgo.go:43-51]). [mirage-crypto-ec] does not normalise, so a
    signature that is correct by every other measure is refused by the node, and
    the failure looks like a signing bug one layer above where it is.

    {!sign_digest} normalises. {!is_low_s} is exposed so that a decoder can ask
    what it was handed rather than assume.

    {2 Randomness}

    None is drawn. Nonces are RFC 6979 deterministic, which keeps
    [mirage-crypto-rng] initialisation off a unikernel's critical path and makes
    a signature reproducible — and therefore comparable against another
    implementation's, which is what the conformance fixtures rely on.

    The trade is real and worth naming: [mirage-crypto-ec] documents power and
    timing attacks against the RFC 6979 computation of [k] and advises supplying
    [k] explicitly from a good source. In an enclave with no entropy service on
    the critical path there is no such source, and a signature that cannot be
    reproduced cannot be checked against the SDK. Determinism wins here; if that
    changes, it changes with a threat model behind it. *)

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
