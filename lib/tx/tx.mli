(** The transaction as it goes on the wire, and as it comes back off it.

    {2 Assembling}

    {!sign} builds the [SignDoc], hashes it, signs it, and frames the result
    around the {i same} body and auth-info bytes the signature covers. There is
    no path through this module that signs one encoding and broadcasts another.

    {2 Decoding}

    {!of_bytes} is what a signer uses on a transaction it did not build. It
    keeps [body_bytes] and [auth_info_bytes] verbatim, so the decoded value can
    be re-emitted unchanged, and decodes them separately for display. A
    transaction whose messages this library cannot read still decodes — with
    those messages opaque — because refusing outright would leave a caller
    unable to see what they were being asked to approve. *)

type t

val sign :
  body:Body.t ->
  auth_info:Auth_info.t ->
  chain_id:Cosmos_types.Chain_id.t ->
  account_number:int64 ->
  key:Cosmos_crypto.private_key ->
  (t, string) result
(** Single-signer. Multi-signer transactions need each party's signature in the
    order their addresses appear, which is a protocol this library does not yet
    implement rather than one it disallows. *)

val of_bytes : base:string -> string -> (t, string) result
(** A serialized [TxRaw]. *)

val to_bytes : t -> string
(** The serialized [TxRaw], ready to broadcast. *)

val body : t -> Body.t
val auth_info : t -> Auth_info.t
val signatures : t -> string list

val hash : t -> string
(** [SHA-256] of {!to_bytes}, 32 bytes — the transaction hash a node indexes by
    and returns from a broadcast. Uppercase hex is the usual rendering, and is
    not applied here. *)

val verify :
  t -> chain_id:Cosmos_types.Chain_id.t -> account_number:int64 -> bool
(** Rebuilds the [SignDoc] from the kept bytes and checks every signature
    against the public key in the matching signer info.

    Worth running on a transaction this library just built: it is the check that
    the bytes carried out are the bytes that were signed, and it fails if
    anything reshaped them in between. [false] when a signer has no parsable
    public key, since an unattributable signature is not a verified one. *)
