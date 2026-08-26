(** The JSON-RPC 2.0 envelope.

    Pure: {!request} produces the bytes to send and {!response} reads the bytes
    that came back. Neither touches a socket, which is what lets the same code
    run over a Unix file descriptor and a Solo5 vsock. *)

val request : id:int -> 'a Method.t -> string
(** The request body. *)

val response : 'a Method.t -> string -> ('a, Error.t) result
(** Unwraps the envelope, distinguishes an envelope error from an application
    one, and runs the method's decoder on the result.

    The [id] is deliberately not checked against the request's. Over a
    request-response transport there is one outstanding call and the answer is
    to it; over a multiplexed one the transport is what pairs them, and doing it
    here as well would just be a second place to get it wrong. *)
