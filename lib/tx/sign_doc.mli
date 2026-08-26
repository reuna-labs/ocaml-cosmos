(** [SignDoc] — the bytes a Cosmos signature actually covers.

    {2 The bytes that were signed are the bytes that go out}

    [SignDoc] binds [body_bytes] and [auth_info_bytes] as opaque byte strings,
    alongside [chain_id] and [account_number]. [TxRaw] then carries those same
    two byte strings to the node.

    So {!make} takes a {!Body.t} and an {!Auth_info.t} rather than two strings,
    and takes their kept bytes. Handing it raw strings would let a caller
    display one transaction and sign another with nothing in the types to stop
    them.

    Protobuf admits encodings that decode alike and re-encode differently —
    field order, non-minimal varints, unknown fields that survive a round trip —
    so a re-encode of a decoded body is not reliably the body that was decoded.
    Here that matters twice over, because the signature covers a concatenation
    of both.

    {2 What is signed is not what is broadcast}

    A [SignDoc] is never transmitted. It is constructed on both sides — here,
    and again by the node from the [TxRaw] it received plus the chain id and
    account number it already knows — and the two must agree byte for byte. That
    is why {!to_bytes} matters and why the conformance fixtures pin it. *)

type t

val make :
  body:Body.t ->
  auth_info:Auth_info.t ->
  chain_id:Cosmos_types.Chain_id.t ->
  account_number:int64 ->
  t

val of_bytes : string -> (t, string) result
(** Decodes a serialized [SignDoc] — what a signer is handed when it did not
    build the transaction itself.

    The two byte strings are kept exactly as they arrived. Nothing here
    re-encodes them, and {!to_bytes} is deliberately {i not} guaranteed to
    reproduce the input: a payload carrying a non-canonical protobuf encoding
    decodes to the same meaning and would re-encode to different bytes. The
    meaning is what gets reviewed; the original bytes are what gets signed. *)

val body_bytes : t -> string
val auth_info_bytes : t -> string
val chain_id : t -> Cosmos_types.Chain_id.t
val account_number : t -> int64

val to_bytes : t -> string
(** The serialized [SignDoc]. *)

val digest : t -> string
(** [SHA-256] of {!to_bytes} — 32 bytes, and what {!Cosmos_crypto.sign_digest}
    is given. The SDK hashes with SHA-256 before signing
    ([secp256k1_nocgo.go:17]); doing it here rather than inside the signer keeps
    the choice of hash visible at the call site. *)
