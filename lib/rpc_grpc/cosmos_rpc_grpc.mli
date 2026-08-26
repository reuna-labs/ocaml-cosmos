(** The Cosmos gRPC services over any flow — including a Solo5 vsock.

    {2 Two wire paths, one set of types}

    Everything here decodes into the values {!Cosmos_rpc.Query} produces over
    CometBFT JSON-RPC. That is what makes the two comparable rather than merely
    coexisting: a disagreement between them about the same account is a finding
    about this library, not a difference of opinion between two clients.

    gRPC is the better path where it is available — it carries protobuf without
    a base64 round trip through JSON, and its errors are typed. It is not always
    available: a node exposes it on a different port, and many public endpoints
    expose only the JSON-RPC one. Hence both.

    {2 Not [h2-mirage]}

    It would do the functorising, and pull roughly 48 packages doing it —
    [conduit-mirage], [tcpip], [tls-mirage], [x509], [dns-client], [vchan],
    [xenstore] — because it assumes a full network stack. The confidential Solo5
    targets have a vsock instead. What [h2] needs from a transport is
    [Gluten_lwt.IO], which is four functions, so {!Io_of_flow} implements those
    over a flow directly. *)

module Io_of_flow = Io_of_flow
module Method = Method_grpc
module Simulation = Simulation

module type FLOW = Io_of_flow.FLOW

module Make (F : FLOW) : sig
  type t

  val create : ?scheme:string -> F.flow -> t Lwt.t
  (** [scheme] is ["http"] unless TLS is underneath, in which case the caller
      composed it and knows. *)

  val call : t -> 'a Method.t -> ('a, Cosmos_rpc.Error.t) result Lwt.t

  val flow : t -> F.flow
  (** The flow underneath. A caller that supplied it usually still holds it;
      this is for one that did not. *)

  val shutdown : t -> unit Lwt.t
  (** Closes the HTTP/2 connection. The flow itself belongs to the caller — on a
      unikernel it comes from a device the guest configured, and tearing it down
      from inside an RPC client would take it away from whoever else holds it.
  *)
end
