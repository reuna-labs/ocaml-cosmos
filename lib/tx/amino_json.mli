(** [SIGN_MODE_LEGACY_AMINO_JSON] -- a second canonical encoding of the same
    transaction.

    Amino JSON is what Ledger devices and several app-chain paths still require,
    so a signer that cannot produce it cannot serve those callers, and one that
    cannot decode it cannot refuse it intelligibly. It is not JSON in the
    ordinary sense: keys are sorted, there is no whitespace, empty fields are
    omitted, and the type names are amino names such as [cosmos-sdk/MsgSend]
    which do not match the protobuf [type_url].

    The writer is hand-written rather than built on a JSON library, because it
    is a canonical encoder over data that is about to be signed and because that
    is what keeps [yojson] out of the offline closure.

    Note for anyone reading the schema pin: [SIGN_MODE_TEXTUAL] was removed in
    cosmos-sdk v0.55.0 -- [signing.proto] now reserves field 2 and the name. It
    is not implemented here and will not be.

    Skeleton: G10 L2 work. *)

val of_sign_doc : chain_id:string -> string
