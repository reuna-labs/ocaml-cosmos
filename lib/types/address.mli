(** Cosmos addresses.

    An address is raw bytes plus a {!Cosmos_types.Prefix.t}. Its bech32 spelling
    is a rendering of that pair, not the thing itself — which matters because
    the same bytes under a different prefix are a different address with a
    different meaning, and nothing in the encoding warns you.

    {2 What the chain accepts, and what a policy should}

    The SDK checks only that an address is non-empty and at most 255 bytes
    ([types/address.go:166-181] at the pinned revision). It does {b not} require
    20 or 32; those are conventions — 20 for a secp256k1 account, 32 for a
    module or derived address — and the SDK's own test suite round-trips a
    ten-byte address.

    So this module decodes what the chain accepts and lets policy be stricter
    than the chain. {!of_bytes} takes 1..255 bytes; {!is_standard_length} is
    what a policy asks when it wants to insist. Refusing the unusual case here
    would mean being unable to read state a node legitimately returns.

    {2 Bech32, not bech32m}

    The SDK decodes with btcutil's [bech32.Decode], which implements BIP-173
    only, and with a 1023-character limit rather than BIP-173's 90
    ([types/bech32/bech32.go:21]). Both are followed here. A bech32m checksum is
    rejected outright: accepting it would let a string built for a Taproot
    output be read as an account. *)

type t

val of_bytes : Prefix.t -> string -> (t, string) result
(** [of_bytes prefix bytes] with [bytes] the raw address, 1..255 of them. *)

val to_bytes : t -> string
val prefix : t -> Prefix.t

val length : t -> int
(** Bytes, not characters. *)

val is_standard_length : t -> bool
(** [true] for the 20-byte secp256k1 form and the 32-byte derived form. A policy
    that requires one of those asks here; the decoder does not. *)

val to_bech32 : t -> string
(** Never raises: every value of this type was checked at construction. *)

val of_bech32 : base:string -> string -> (t, string) result
(** [of_bech32 ~base s] decodes [s] and checks that its human-readable part is
    one of the three prefixes of the chain whose account prefix is [base].

    [base] is required rather than inferred for the reason given in
    {!Cosmos_types.Prefix.of_hrp}: a bare human-readable part does not say which
    chain it belongs to. Passing the chain you believe you are talking to is
    also what turns a cross-chain address paste into an error instead of a
    successful decode. *)

val equal : t -> t -> bool
(** Same bytes {b and} same prefix. *)

val same_bytes : t -> t -> bool
(** Same bytes, whatever the prefixes. This is the cross-prefix hazard made
    checkable: [same_bytes] is [true] and {!equal} is [false] for the account
    and validator spellings of one key, which is exactly the case a reviewer
    needs to see rather than have hidden. *)
