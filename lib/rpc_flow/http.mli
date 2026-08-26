(** Just enough HTTP/1.1 to carry JSON-RPC, as a pure parser.

    Pure so that it can be tested and fuzzed without a socket, and small because
    the surface a JSON-RPC client needs is small: one method, one content type,
    and a body whose length is either declared or chunked.

    {2 Bounded, because the peer chooses the length}

    Every limit here is against a response the node controls. A [Content-Length]
    header can claim anything, a chunked body can go on for ever, and a header
    block can arrive without an end. Each has a cap, and exceeding one is an
    error rather than an allocation. *)

type limits = {
  max_header_bytes : int;  (** Default 64 KiB. *)
  max_body_bytes : int;  (** Default 8 MiB. *)
}

val default_limits : limits

val request : host:string -> path:string -> string -> string
(** A complete [POST]. [Connection: close] is not sent: the caller decides
    whether to reuse the connection, and a client that closed after every
    request would spend a round trip per call. *)

type response = { status : int; body : string }

(** {2 Incremental parsing}

    The transport feeds bytes as they arrive and asks what to do next. Nothing
    here buffers a whole response before looking at it, so an oversized body is
    refused while it is still arriving rather than after. *)

type state

val start : limits -> state

val feed : state -> string -> (state, string) result
(** [Error] on a malformed or oversized response. *)

val result : state -> response option
(** [Some] once the body is complete. *)
