(** secp256k1 signing and address derivation for Cosmos SDK chains.

    {2 One hash, and the signature is not recoverable}

    A Cosmos signature covers [SHA-256] of the serialized [SignDoc] and goes on
    the wire as 64 bytes, [r] then [s]. There is no recovery byte and no
    recovery function here: the public key travels in [SignerInfo], so nothing
    ever needs to derive it from a signature. That is what keeps the reference
    bignum backend, and with it zarith and GMP, out of this closure.

    {2 Low-S is a requirement, not a nicety}

    The SDK rejects a signature whose [s] is above [n/2] as malleable, and
    [mirage-crypto-ec] does not normalise. A signature that is correct by every
    other measure is refused by the node, which looks like a signing bug and is
    not one. {!sign_digest} normalises; {!is_low_s} is exposed so a decoder can
    check what it was handed.

    {2 Two address lengths, and the prefix is not decoration}

    An account address is [RIPEMD160(SHA256(compressed public key))], 20 bytes.
    Some chains use 32-byte addresses. Neither carries its own prefix -- see
    {!Cosmos_types.Prefix} for why that matters.

    {2 Randomness}

    None is drawn. Nonces are RFC 6979 deterministic, which is what keeps
    [mirage-crypto-rng] initialisation off a unikernel's critical path.

    Skeleton: the signatures below are the contract; the bodies are G10 L1 work.
*)

type private_key
type public_key

type signature
(** 64 bytes, [r] then [s], always low-S. *)

val sign_digest : key:private_key -> string -> (signature, string) result
(** [sign_digest ~key digest] signs 32 bytes already computed. Nothing here
    hashes a message: the caller has to have built the [SignDoc] and is the only
    party that knows what was in it. *)

val verify_digest : key:public_key -> signature -> string -> bool
val is_low_s : signature -> bool
val public_key_of_private : private_key -> public_key

val compressed : public_key -> string
(** 33 bytes, SEC 1 compressed. This is the form that goes into
    [cosmos.crypto.secp256k1.PubKey] and the form the address is derived from;
    an uncompressed key derives a different, wrong address. *)

val address_bytes : public_key -> string
(** [RIPEMD160(SHA256(compressed pk))], 20 bytes. *)
