(** What a transport has to be.

    Four functions and a monad. The client is written once against this and
    instantiated over a Unix file descriptor, a Solo5 vsock, or a pair of
    in-memory buffers in a test — which is what makes the confirmation logic
    testable without a socket at all.

    The signature is deliberately this small. Anything richer would let a
    transport make protocol decisions, and the whole arrangement exists so that
    it cannot. *)

module type MONAD = sig
  type 'a t

  val return : 'a -> 'a t
  val bind : 'a t -> ('a -> 'b t) -> 'b t
end

module type S = sig
  type 'a io

  type t
  (** A connection, or something that can produce one. *)

  val call : t -> string -> (string, Error.t) result io
  (** [call t body] sends a JSON-RPC request body and returns the response body.
      Everything about framing, connecting, reconnecting and bounding the
      response size belongs to the implementation. *)
end
