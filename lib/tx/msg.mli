(** The message allow-list.

    Every message in a [TxBody] is a [google.protobuf.Any]: a [type_url] and an
    opaque byte string. The launch allow-list is

    - [/cosmos.bank.v1beta1.MsgSend]
    - [/cosmos.bank.v1beta1.MsgMultiSend]
    - [/ibc.applications.transfer.v1.MsgTransfer]
    - [/cosmwasm.wasm.v1.MsgExecuteContract]

    Anything else decodes as {!Unknown}, reaches the intent layer as {!Unknown},
    and can never satisfy a policy. An app-chain's custom module is not a thing
    this library can explain to a human, and a signer that cannot explain what
    it is signing has no business approving it.

    Skeleton: the variant is the contract; the decoders are G10 L2 work. *)

type t =
  | Send
  | Multi_send
  | Ibc_transfer
  | Wasm_execute
  | Unknown of { type_url : string; value : string }
