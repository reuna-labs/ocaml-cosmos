(** The CometBFT JSON-RPC catalogue.

    A method is a name, its parameters, and a decoder for its result. Bundling
    the three means a caller cannot pair one method's parameters with another's
    decoder, and means the transport does not need to know anything about any of
    them — it moves a request in and a response out.

    {2 What is here, and what is not}

    Enough to hold an account and move funds: node identity, an ABCI query,
    broadcast, and a transaction lookup. Not the block, validator, consensus or
    evidence surfaces — a signer does not need them, and each one is more
    untrusted JSON to parse. *)

type 'a t

val map : ('a -> ('b, Error.t) result) -> 'a t -> 'b t
(** Post-process a method's result, keeping its name and parameters.

    This is how {!Cosmos_rpc.Query} builds a typed query out of a raw ABCI one:
    the request is unchanged, and the decoder gains a second stage that reads
    the protobuf inside. Keeping [t] abstract and offering this instead means a
    caller cannot pair one method's parameters with another's decoder, which is
    the mistake the type exists to prevent. *)

val name : 'a t -> string
val params : 'a t -> (string * Json.t) list
val decode : 'a t -> Json.t -> ('a, Error.t) result

(** {2 Node identity} *)

type status = {
  chain_id : Cosmos_types.Chain_id.t;
  node_version : string;
  latest_block_height : int64;
  latest_block_time : string;
  catching_up : bool;
}

val status : status t
(** Ask before anything else. [chain_id] is what a caller checks against the
    profile it thinks it is using, and [catching_up] is what stops a signer
    building on a view of the chain that is hours old. *)

(** {2 ABCI queries} *)

type abci_response = { value : string; height : int64 }

val abci_query : path:string -> data:string -> abci_response t
(** A gRPC query method reached through CometBFT. [path] is the fully-qualified
    service method, e.g. ["/cosmos.auth.v1beta1.Query/Account"], and [data] is
    the encoded request message.

    A non-zero ABCI code decodes as {!Error.Abci} rather than as a value: the
    node answered, and the answer was no. *)

(** {2 Broadcast} *)

type broadcast_result = {
  code : int;
  codespace : string;
  log : string;
  hash : string;
}

val broadcast_tx_sync : string -> broadcast_result t
(** [broadcast_tx_sync tx_bytes]. Returns when the transaction has passed — or
    failed — [CheckTx], which is {b not} execution.

    A [code] of 0 here means the transaction entered a mempool. It has not run,
    it may still fail, and it may never be included at all. The result is
    deliberately not a {!Confirmation.t} for that reason; turning one into the
    other is {!Confirmation.of_broadcast}, which only ever produces [In_mempool]
    or [Failed].

    [broadcast_tx_commit] is not offered. It blocks the node until the
    transaction is in a block and times out under exactly the conditions where
    an answer matters most. *)

(** {2 Lookup} *)

type tx_result = {
  hash : string;
  height : int64;
  code : int;
  codespace : string;
  log : string;
  gas_wanted : int64;
  gas_used : int64;
}

val tx : hash:string -> tx_result t
(** [hash] is the 32 raw bytes, not the hex rendering. A transaction that is not
    found is {!Error.Rpc}, because CometBFT reports it in the envelope rather
    than as an ABCI code. *)
