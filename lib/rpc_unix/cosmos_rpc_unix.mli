(** The CometBFT JSON-RPC client over Unix TCP, Unix-domain sockets, or
    certificate-verified TLS.

    The HTTP implementation remains {!Cosmos_rpc_flow.Make}; this package only
    dials the host transport and, for HTTPS, wraps it in [tls-lwt]. The default
    HTTPS path uses the operating system trust store through [ca-certs], sends
    SNI, and verifies the provider hostname. A caller can supply a narrower
    {!X509.Authenticator.t} when it pins a private provider or deployment CA.

    TLS is intentionally isolated here. The signed-data, RPC, flow and gRPC
    packages retain their Unix-free and GMP-free closures and still compose with
    [Tls_mirage.Make] when a Mirage deployment supplies its own trust anchors.
*)

module Endpoint : sig
  type scheme = [ `Http | `Https ]
  type t

  val of_string : string -> (t, string) result
  (** Parses [http://] and [https://] endpoints, including an optional port,
      path and query. For compatibility, a value without a scheme is plain HTTP
      on CometBFT's conventional port 26657. User information and fragments are
      rejected. *)

  val scheme : t -> scheme
  val host : t -> string
  val port : t -> int
  val path : t -> string
  val host_header : t -> string
end

type t

val create :
  ?limits:Cosmos_rpc_flow.Http.limits ->
  ?path:string ->
  host:string ->
  Lwt_unix.file_descr ->
  t
(** Creates a client over an already connected plain Unix file descriptor. *)

val call : t -> string -> (string, Cosmos_rpc.Error.t) result Lwt.t

val request :
  t -> 'a Cosmos_rpc.Method.t -> ('a, Cosmos_rpc.Error.t) result Lwt.t

(** {2 Dialling} *)

val connect_uri :
  ?limits:Cosmos_rpc_flow.Http.limits ->
  ?authenticator:X509.Authenticator.t ->
  ?host_header:string ->
  string ->
  (t, Cosmos_rpc.Error.t) result Lwt.t
(** Dials an HTTP or HTTPS URI. HTTPS uses the system trust store unless
    [authenticator] is supplied. The TLS peer name always comes from the URI;
    [host_header] only overrides HTTP routing, for example behind a proxy. *)

val connect_tls :
  ?limits:Cosmos_rpc_flow.Http.limits ->
  ?authenticator:X509.Authenticator.t ->
  ?host_header:string ->
  ?path:string ->
  string ->
  int ->
  (t, Cosmos_rpc.Error.t) result Lwt.t

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
