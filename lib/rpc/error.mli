(** What can go wrong, kept apart.

    The distinction that matters most here is between {!Rpc} and {!Abci}: one
    means the node did not answer, the other means it answered and the answer
    was no. A client that collapsed them would retry a query that will never
    succeed, or give up on one that would. *)

type t =
  | Transport of string
      (** The bytes never arrived, or arrived unusable. Retrying may work. *)
  | Malformed of string
      (** They arrived and were not what the protocol says. Retrying will not
          help, and this is the case worth logging loudly: it means the node,
          the pin, or this library is wrong. *)
  | Rpc of { code : int; message : string }
      (** A JSON-RPC envelope error — the node refused the request itself. *)
  | Abci of { code : int; codespace : string; log : string }
      (** The node answered, and the application said no. [code] 0 never appears
          here: that is a success. *)

val pp : Format.formatter -> t -> unit
val to_string : t -> string

val is_retryable : t -> bool
(** [true] only for {!Transport}. Nothing else gets better by being asked again
    — an [Abci] refusal is a decision, and a [Malformed] response is a
    disagreement about the protocol. *)
