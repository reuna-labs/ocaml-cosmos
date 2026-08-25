(** The submission state machine.

    Pure: it consumes responses and produces the next request, and never talks
    to a socket. The transports interpret it.

    {2 The sequence is the hazard}

    [account_number] binds the account and [sequence] binds the transaction.
    Both are fetched, not invented. What makes this harder than a nonce is that
    a rejected transaction {i may or may not} have consumed the sequence:
    rejection in [CheckTx] does not, rejection in [DeliverTx] does. Guessing
    produces either a replay -- signing a second transaction with a sequence the
    chain has already used, which is refused -- or a permanent gap, which stalls
    the account until something fills it.

    So a failure returns to account discovery rather than incrementing locally,
    and a rebuild re-signs rather than replaying signed bytes.

    Skeleton: G10 L3 work. *)

type t
