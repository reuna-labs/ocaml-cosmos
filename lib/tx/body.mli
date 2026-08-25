(** [TxBody] — what the transaction does, and until when.

    {2 The bytes are the value}

    A [TxBody] built here is serialized once, and that serialization is kept. A
    [TxBody] decoded from the wire keeps the bytes it arrived in. {!to_bytes}
    returns the kept bytes in both cases, never a re-encode.

    This is not fastidiousness. [SignDoc] covers [body_bytes] as an opaque
    string, so a re-encode that differs anywhere — a field order, a non-minimal
    varint, an unknown field that survived the round trip — is a signature over
    one transaction attached to another. The node would reject it, and the
    person debugging would be looking at the signer.

    {2 Extension options are authority}

    [extension_options] and [non_critical_extension_options] are [Any] lists
    that almost every transaction leaves empty, and that a chain can use to
    change what a transaction means. They are surfaced as opaque pairs rather
    than hidden, so a policy can refuse a transaction carrying any. *)

type t

val make :
  messages:Msg.t list ->
  ?memo:string ->
  ?timeout_height:int64 ->
  ?timeout_timestamp:int64 ->
  ?unordered:bool ->
  unit ->
  (t, string) result
(** [timeout_timestamp] is seconds since the Unix epoch, and is required when
    [unordered] is set — an unordered transaction has no sequence to bound it,
    so the timestamp is the only thing that stops it being replayed for ever.
    That rule is the SDK's, and it is enforced here rather than discovered at
    the node.

    A body with no messages is refused: it is valid protobuf and means nothing.
*)

val of_bytes : base:string -> string -> (t, string) result
(** Decodes, and keeps [string] verbatim for {!to_bytes}. *)

val to_bytes : t -> string
(** The kept bytes. Never a re-encode — see above. *)

val messages : t -> Msg.t list
val memo : t -> string
val timeout_height : t -> int64
val timeout_timestamp : t -> int64
val unordered : t -> bool

val extension_options : t -> (string * string) list
(** [(type_url, value)] pairs, opaque. *)

val non_critical_extension_options : t -> (string * string) list

val is_approvable : t -> bool
(** Every message is approvable, and neither extension list carries anything. A
    policy asks this before it asks anything else. *)
