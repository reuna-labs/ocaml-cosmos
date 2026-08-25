(** [SignDoc] -- the bytes a Cosmos signature actually covers.

    {2 The bytes that were signed are the bytes that go out}

    [SignDoc] binds [body_bytes] and [auth_info_bytes] as opaque byte strings,
    alongside [chain_id] and [account_number]. [TxRaw] then carries those same
    two byte strings to the node.

    They are retained, never re-encoded. Protobuf admits encodings that decode
    alike and re-encode differently -- field order, non-minimal varints, unknown
    fields that survive a round trip -- so re-serializing a decoded [TxBody] can
    produce different bytes from the ones the signature covers. The node would
    then verify a signature over one transaction while executing another, or
    more likely reject it outright and leave the caller debugging the wrong
    layer.

    This is [ocaml-tron]'s rule about [raw_data], and here it is load-bearing
    twice over: the signature covers a concatenation of both byte strings.

    Skeleton: the signatures below are the contract; the bodies are G10 L2 work.
*)

type t

val make :
  body_bytes:string ->
  auth_info_bytes:string ->
  chain_id:string ->
  account_number:int64 ->
  t

val to_bytes : t -> string
(** The serialized [SignDoc]. *)

val digest : t -> string
(** [SHA-256] of {!to_bytes} -- 32 bytes, and what {!Cosmos_crypto.sign_digest}
    is given. *)
