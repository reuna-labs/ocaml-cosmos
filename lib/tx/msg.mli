(** The message allow-list.

    Every message in a [TxBody] is a [google.protobuf.Any]: a [type_url] and an
    opaque byte string. Four of them can be read here:

    - [/cosmos.bank.v1beta1.MsgSend]
    - [/cosmos.bank.v1beta1.MsgMultiSend]
    - [/ibc.applications.transfer.v1.MsgTransfer]
    - [/cosmwasm.wasm.v1.MsgExecuteContract]

    Anything else becomes {!Opaque}, reaches the intent layer as {!Opaque}, and
    can never satisfy a policy. There are roughly a hundred Cosmos app-chains
    with their own modules, and a signer that cannot explain what a message does
    has no business approving it.

    {2 Recognised is not the same as readable}

    {!Opaque} carries a [why]. A [type_url] nobody here has heard of and a
    [type_url] we know whose payload will not parse are different situations —
    the second means the node sent something wrong, or that the schema pin has
    moved — and both are equally unapprovable, so both land in the same
    constructor with the reason kept rather than discarded.

    {2 Addresses need to know their chain}

    Bech32 carries a prefix but not the chain it belongs to, so decoding takes
    the account prefix — see {!Cosmos_types.Address.of_bech32}. One address
    escapes this: an IBC transfer's [receiver] is on the {i destination} chain,
    under a prefix this one cannot know, so it stays a string and is displayed
    as one. *)

module Address = Cosmos_types.Address
module Coin = Cosmos_types.Coin

type send = {
  from_address : Address.t;
  to_address : Address.t;
  amount : Coin.t list;
}

type io = { address : Address.t; coins : Coin.t list }
type multi_send = { inputs : io list; outputs : io list }
type timeout_height = { revision_number : int64; revision_height : int64 }

type ibc_transfer = {
  source_port : string;
  source_channel : string;
  token : Coin.t;
  sender : Address.t;
  receiver : string;
      (** On the destination chain, under a prefix this chain cannot know. Not
          an {!Address.t} for that reason: pretending to have validated it would
          be worse than plainly not having. *)
  timeout_height : timeout_height;
  timeout_timestamp : int64;  (** Nanoseconds since the Unix epoch. *)
  memo : string;
}

type wasm_execute = {
  sender : Address.t;
  contract : Address.t;
  msg : string;
      (** The contract call, as JSON bytes. Displayed, never interpreted: there
          is no trusted source for a contract's schema at launch, so this
          library cannot say what the call does. *)
  funds : Coin.t list;
}

type t =
  | Send of send
  | Multi_send of multi_send
  | Ibc_transfer of ibc_transfer
  | Wasm_execute of wasm_execute
  | Opaque of { type_url : string; value : string; why : string }

val type_url : t -> string
(** The canonical [type_url], including for {!Opaque}. *)

val of_any : base:string -> type_url:string -> value:string -> t
(** Never fails. A payload that cannot be read becomes {!Opaque} with the
    reason, which is the only honest outcome: refusing to decode the surrounding
    transaction would make a single unreadable message hide everything else in
    it. *)

val to_any : t -> (string * string, string) result
(** [(type_url, value)]. An {!Opaque} message re-emits the bytes it was built
    from, unchanged. *)

val is_approvable : t -> bool
(** [false] for {!Opaque}, [true] otherwise. Not a policy — a policy decides
    whether {i this} transfer is acceptable. This is the prior question of
    whether the message can be described at all. *)
