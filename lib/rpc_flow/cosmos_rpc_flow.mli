(** CometBFT JSON-RPC over any [Mirage_flow.S] -- including a Solo5 vsock.

    Skeleton: G10 L3 work. *)

module Make (_ : Mirage_flow.S) : sig
  type t
end
