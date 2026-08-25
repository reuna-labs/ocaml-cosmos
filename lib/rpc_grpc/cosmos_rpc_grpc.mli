(** The Cosmos gRPC query and tx services over any [Mirage_flow.S].

    Decodes into the same typed values {!Cosmos_rpc} produces over CometBFT
    JSON-RPC, so the two wire paths can be compared rather than merely
    coexisting.

    Skeleton: G10 L3 work. *)

module Make (_ : Mirage_flow.S) : sig
  type t
end
