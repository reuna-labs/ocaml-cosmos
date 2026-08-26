(** Getting a transaction onto a chain, as a pure state machine.

    It consumes responses and produces the next request. It never talks to a
    socket, never sleeps and never reads a clock, so the transports interpret it
    and the tests drive it directly — which is what makes the awkward cases
    below testable at all.

    {2 The sequence is the hazard}

    [account_number] binds the account and [sequence] binds the transaction.
    Both are fetched, never invented. What makes this harder than an Ethereum
    nonce is that a rejected transaction {b may or may not} have consumed the
    sequence:

    - rejected in [CheckTx] — a broadcast returning a non-zero code — the
      sequence was {i not} consumed;
    - rejected in delivery — a broadcast returning 0, and then a transaction
      that lands in a block with a non-zero code — the sequence {i was}
      consumed, and the fee was taken.

    Guessing either way is a real failure. Assume consumed when it was not and
    every later transaction carries a sequence the chain has not reached, so
    nothing confirms until something fills the gap. Assume not consumed when it
    was and the next transaction reuses a spent sequence and is rejected.

    So this machine never increments locally across a failure. It goes back and
    asks, and the answer is authoritative because the chain is the thing
    counting.

    {2 A retry re-signs}

    A rebuild produces different bytes — a new sequence, possibly a new timeout
    — so it needs a new signature. There is deliberately no path that
    re-broadcasts bytes that were signed for a state that has moved. *)

module Address = Cosmos_types.Address
module Chain_id = Cosmos_types.Chain_id

type config = {
  chain_id : Chain_id.t;
  signer : Address.t;
  max_rebuilds : int;
      (** How many times to go back for a fresh sequence and re-sign. Bounded
          because an unbounded retry against a node that always says no is an
          expensive way to do nothing. *)
  max_polls : int;
      (** How many times to ask whether a broadcast transaction has landed. *)
}

type request =
  | Check_node
      (** Ask [status]. The chain id is checked against the config before
          anything is signed: a transaction built for the wrong chain is the one
          mistake that cannot be undone afterwards. *)
  | Fetch_account
  | Build_and_sign of { account_number : int64; sequence : int64 }
      (** Handed back to the caller, because signing is not this machine's
          business. It says what to sign for, not how. *)
  | Broadcast of string
  | Poll of { hash : string }

type outcome =
  | Delivered of { hash : string; height : int64; gas_used : int64 }
  | Rejected of {
      stage : [ `Check | `Deliver ];
      code : int;
      codespace : string;
      log : string;
    }
      (** [stage] is the whole point: [`Check] left the sequence unconsumed and
          [`Deliver] did not. A caller that needs to know whether its funds
          moved needs to know which. *)
  | Gave_up of string

type t

val start : config -> t

val resume : config -> hash:string -> t
(** Pick up polling a transaction that was already broadcast.

    {2 What is worth persisting across a restart, and what is not}

    Exactly one thing: the hash. Everything else this machine holds is
    re-derivable from the chain and is {i safer} re-derived — the account number
    and sequence because the chain is the thing counting them, and the signed
    bytes because they were signed for a state that may have moved while the
    process was down.

    A signer that persisted its whole state and resumed mid-broadcast would be
    re-broadcasting bytes it can no longer justify. A signer that persisted
    nothing would have no way to find out what happened to a transaction it had
    already sent, which is the one question a restart leaves open — and the
    expensive one, because the answer might be "it went through".

    So: write the hash before broadcasting, and resume with it afterwards. If
    the transaction never arrived, polling ends in {!Gave_up} and the caller
    starts again from {!start}; if it did, this finds out. *)

val next : t -> request
(** What to do now. *)

(** {2 Feeding it answers} *)

val on_status : t -> Method.status -> t
val on_account : t -> Query.account_result -> t

val on_signed : t -> string -> t
(** The signed transaction bytes, from whoever performed the {!Build_and_sign}.
*)

val on_broadcast : t -> Method.broadcast_result -> t

val on_tx : t -> (Method.tx_result, Error.t) result -> t
(** A poll. An {!Error.Rpc} here is the ordinary "not found yet" answer, since
    CometBFT reports a missing transaction in the envelope; it is not a failure
    and the machine keeps polling. *)

val on_error : t -> Error.t -> t
(** Anything that went wrong at the transport. Retryable errors are retried up
    to the budget; the rest end it. *)

val finished : t -> outcome option

val sequence_consumed : t -> bool option
(** After a {!Rejected} outcome: whether the sequence was spent. [None] while
    still running, since the answer is not known until the machine stops. *)
