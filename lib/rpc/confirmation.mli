(** How far a transaction has actually got.

    Tagged, not boolean, and the three states below are routinely conflated:

    - {!In_mempool} -- [broadcast_tx_sync] returned code 0. That means the node
      accepted the bytes into {i a} mempool. It has not executed, and a
      transaction that fails in delivery reports success here.
    - {!Delivered} -- a transaction query returns code 0 at a height. This is
      the first state in which the transaction has done anything.
    - {!Final} -- delivered, and buried under enough blocks for the product to
      accept it. How many is the caller's decision, not this library's.

    A failed delivery is {!Failed} and carries the ABCI code and log, which is
    the only place the reason ever appears.

    Skeleton: G10 L3 work. *)

type t =
  | Unknown
  | In_mempool
  | Delivered of { height : int64 }
  | Final of { height : int64; depth : int }
  | Failed of { code : int; codespace : string; log : string }
