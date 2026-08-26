(** CometBFT JSON-RPC over any [Mirage_flow.S] — including a Solo5 vsock.

    {2 Why a flow and not an HTTP client}

    Not a preference. The confidential Solo5 targets forbid [NET_BASIC]
    outright, and [sptmac] has no networking at all, so a vsock is the only
    transport available there. A client functorised over an HTTP library assumes
    a TCP stack and cannot reach one; a client functorised over a flow can. TLS
    composes as [Tls_mirage.Make] over the same signature, and so does a pair of
    in-memory buffers in a test.

    {2 What this package owns}

    The socket, and nothing else. The method catalogue, the JSON-RPC envelope,
    the confirmation states and the submission state machine are all in
    [cosmos-rpc] and are pure. This turns a request into bytes on a flow and
    bytes on a flow back into a response, under limits the peer does not choose.
*)

module Http = Http

(** What this client needs from a flow: read, write, and a way to print what
    went wrong.

    Not [Mirage_flow.S] itself, for two reasons. Its [write_error] is a private
    row type, so applying a functor over it to a concrete flow does not
    typecheck without restating the whole signature. And requiring [shutdown],
    [close] and [writev] would demand things this client never calls and rule
    out flows that are perfectly usable — a pair of in-memory buffers in a test,
    for one.

    Every [Mirage_flow.S] satisfies this structurally, so nothing that could
    have been passed before is excluded. It is the same reasoning that keeps
    [h2-mirage] out of the gRPC transport: take the four functions, not the
    stack they come attached to. *)
module type FLOW = sig
  type flow
  type error
  type write_error

  val pp_error : error Fmt.t
  val pp_write_error : write_error Fmt.t
  val read : flow -> (Cstruct.t Mirage_flow.or_eof, error) result Lwt.t
  val write : flow -> Cstruct.t -> (unit, write_error) result Lwt.t
end

module Make (Flow : FLOW) : sig
  type t

  val create :
    ?limits:Http.limits -> ?path:string -> host:string -> Flow.flow -> t
  (** [host] goes in the [Host] header. It is required even over a vsock, where
      it names nothing reachable: HTTP/1.1 requires the header, and CometBFT
      rejects a request without one. *)

  val call : t -> string -> (string, Cosmos_rpc.Error.t) result Lwt.t
  (** Sends a JSON-RPC body and reads the response body.

      One call at a time on one flow. HTTP/1.1 pipelining is not used, so a
      caller wanting concurrency wants more flows. *)

  val request :
    t -> 'a Cosmos_rpc.Method.t -> ('a, Cosmos_rpc.Error.t) result Lwt.t
  (** {!call} with the envelope and the method's decoder applied. This is what a
      caller normally wants. *)
end
