(** How far a transaction has actually got.

    Tagged, not boolean, because the states below are routinely conflated and
    the differences cost money:

    - {!Unknown} — nothing has been heard. It may be in a mempool, it may never
      have arrived, and there is no way to tell from here.
    - {!In_mempool} — [broadcast_tx_sync] returned code 0. That means a node
      accepted the bytes into {i a} mempool. It has not executed, it may fail,
      and it may never be included at all.
    - {!Delivered} — a transaction query returns code 0 at a height. This is the
      first state in which the transaction has done anything.
    - {!Final} — delivered, and the caller's conditions for trusting that are
      met. See below, because those conditions are not what they would be on
      Bitcoin.
    - {!Failed} — it landed in a block and the application rejected it. The fee
      was taken and the sequence was consumed.

    {2 Finality on a CometBFT chain is not depth}

    Cosmos chains run CometBFT, which is a BFT consensus with
    {b instant finality}: a block that is committed is committed, and there is
    no heaviest-chain rule under which a competing fork could displace it.
    Waiting for confirmations the way one waits on Bitcoin is answering a
    question this protocol does not ask.

    What waiting {i does} buy is protection against the two things that can
    still go wrong, and neither is a reorg:

    - the node is lying, or is behind and reporting an old view. A transaction
      it claims at height H either is there or is not, and more blocks make the
      lie more expensive to sustain but never impossible;
    - consensus itself failed — more than a third of voting power was Byzantine,
      or the chain halted and was restarted from a rolled-back state by social
      agreement. Rare, real, and not something depth fixes.

    So {!required_depth} is a statement about how much a product distrusts the
    node it is talking to, not about consensus mechanics. Zero is a defensible
    choice against a node you run yourself. It is not defensible against a
    public endpoint, which is why there is no default. *)

type t =
  | Unknown
  | In_mempool
  | Delivered of { height : int64 }
  | Final of { height : int64; depth : int }
  | Failed of { code : int; codespace : string; log : string }

val of_broadcast : Method.broadcast_result -> t
(** Only ever {!In_mempool} or {!Failed}. A broadcast cannot produce
    {!Delivered}, and a function that could would be an invitation to treat one
    as the other. *)

val of_tx : Method.tx_result -> tip:int64 -> required_depth:int -> t
(** [tip] is the chain's current height, from {!Method.status}. [required_depth]
    is the caller's, for the reasons above.

    A transaction at a height {i above} the tip is reported as {!Delivered}
    rather than {!Final} and never with a negative depth: a node claiming to
    have executed something it has not yet reached is a node to believe less,
    not more. *)

val is_final : t -> bool

val is_settled : t -> bool
(** [true] once the outcome cannot change: {!Final} or {!Failed}. What a caller
    polls until. *)

val pp : Format.formatter -> t -> unit
