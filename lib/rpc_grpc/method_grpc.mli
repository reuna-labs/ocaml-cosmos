(** A gRPC method: where it lives, and how to encode and decode it.

    The same shape as {!Cosmos_rpc.Method} and for the same reason — bundling
    the service, the method name, the request encoder and the response decoder
    means a caller cannot pair one method's request with another's decoder. *)

type 'a t = {
  service : string;  (** e.g. ["cosmos.auth.v1beta1.Query"] *)
  rpc : string;  (** e.g. ["Account"] *)
  request : string;  (** The encoded request message. *)
  decode : string -> ('a, Cosmos_rpc.Error.t) result;
}

val account :
  base:string -> Cosmos_types.Address.t -> Cosmos_rpc.Query.account_result t

val balance :
  base:string ->
  Cosmos_types.Address.t ->
  denom:Cosmos_types.Denom.t ->
  Cosmos_types.Coin.t t

val simulate : tx_bytes:string -> Simulation.t t
(** [cosmos.tx.v1beta1.Service/Simulate]. Runs the transaction without
    committing it and reports what it would cost.

    The transaction has to be signed to simulate, even though the signature is
    not checked — the node needs a well-formed [TxRaw]. A signature over a
    sequence that is about to change is therefore fine here and is not fine to
    broadcast, which is why simulation happens before the real signing rather
    than instead of it. *)
