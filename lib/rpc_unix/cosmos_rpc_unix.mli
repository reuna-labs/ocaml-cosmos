(** The CometBFT JSON-RPC client over a Unix socket.

    This is {!Cosmos_rpc_flow.Make} instantiated over [Mirage_flow_unix.Fd] and
    nothing more. The interesting property is what is {e absent}: there is no
    Unix-specific client code, so the Unix path and the unikernel path are the
    same implementation with a different flow underneath. If they were two
    implementations, only one of them would be the tested one.

    Dialling is the exception, and it lives here rather than one layer up on
    purpose: a unikernel's connection comes from a device it owns, and putting a
    [getaddrinfo] into [cosmos-rpc-flow] would be a Unix dependency in the one
    layer that must not have one.

    TLS is not wired here. It composes as [Tls_mirage.Make] over the same flow
    signature, and doing it properly means deciding where the trust anchors come
    from — a deployment question, and supplying a default would be answering it
    wrongly. *)

type t

val create :
  ?limits:Cosmos_rpc_flow.Http.limits ->
  ?path:string ->
  host:string ->
  Lwt_unix.file_descr ->
  t

val call : t -> string -> (string, Cosmos_rpc.Error.t) result Lwt.t

val request :
  t -> 'a Cosmos_rpc.Method.t -> ('a, Cosmos_rpc.Error.t) result Lwt.t

(** {2 Dialling} *)

val connect_tcp :
  ?limits:Cosmos_rpc_flow.Http.limits ->
  ?host_header:string ->
  ?path:string ->
  string ->
  int ->
  (t, Cosmos_rpc.Error.t) result Lwt.t

val connect_unix :
  ?limits:Cosmos_rpc_flow.Http.limits ->
  ?host_header:string ->
  ?path:string ->
  string ->
  (t, Cosmos_rpc.Error.t) result Lwt.t
(** A node's local socket. The [Host] header still has to be something: HTTP/1.1
    requires it and CometBFT rejects a request without one. *)

val close : t -> unit Lwt.t
