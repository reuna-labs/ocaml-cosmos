(** [SIGN_MODE_LEGACY_AMINO_JSON] — a second canonical encoding of the same
    transaction.

    Amino JSON is what Ledger devices and several app-chain paths still require,
    so a signer that cannot produce it cannot serve those callers, and one that
    cannot decode it cannot refuse it intelligibly.

    It is not JSON in the ordinary sense. Keys are sorted, there is no
    whitespace, integers are decimal {i strings}, and the type names are amino
    names — [cosmos-sdk/MsgSend], [wasm/MsgExecuteContract] — which do not match
    the protobuf [type_url]. They come from the [(amino.name)] option in the
    pinned [.proto] files, not from a table someone typed out.

    {2 The three rules that are easy to get wrong}

    The [amino.*] options in the schema govern this encoding, and three of them
    change the output in ways a reading of the message alone would not suggest:

    - [(amino.dont_omitempty)] keeps a field that is otherwise dropped when
      empty. [MsgSend.amount], [MsgMultiSend.inputs] and [outputs],
      [MsgTransfer.token] and [timeout_height], and [Coin.amount] all carry it.
    - [(amino.encoding) = "inline_json"] splices a bytes field in as JSON rather
      than base64-encoding it. CosmWasm's [msg] carries it — and the SDK
      re-serialises the spliced JSON, which {b sorts its keys}. So a contract
      call written [{"recipient":…,"amount":…}] signs as
      [{"amount":…,"recipient":…}], and a signer that passed the caller's bytes
      through unchanged would sign something the node does not compute.
    - [timeout_height] appears at the {i top level} of the document, beside
      [memo] and [sequence], as well as inside the body.

    Each of those was established from the SDK's own encoder — see
    [conformance/simd] — rather than from reading the schema, which is the only
    way to be sure of any of them.

    {2 Not [SIGN_MODE_TEXTUAL]}

    Withdrawn upstream: cosmos-sdk v0.55.0 reserved field 2 and the name. *)

val amino_name : Msg.t -> (string, string) result
(** The [(amino.name)] for a message, or an error for one outside the allow-list
    — which cannot be signed in this mode at all, since there is no name to put
    in the document. *)

val sign_bytes :
  body:Body.t ->
  auth_info:Auth_info.t ->
  chain_id:Cosmos_types.Chain_id.t ->
  account_number:int64 ->
  (string, string) result
(** The bytes a [SIGN_MODE_LEGACY_AMINO_JSON] signature covers.

    [sequence] comes from the first signer in [auth_info]; the document has one
    sequence, so a multi-signer transaction cannot be represented and is refused
    rather than silently signed for the first signer alone. *)

val digest :
  body:Body.t ->
  auth_info:Auth_info.t ->
  chain_id:Cosmos_types.Chain_id.t ->
  account_number:int64 ->
  (string, string) result
(** [SHA-256] of {!sign_bytes}. *)
