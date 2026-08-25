(** [AuthInfo] — who signs, in what mode, and who pays.

    Kept byte-for-byte for the same reason as {!Body}: [SignDoc] covers
    [auth_info_bytes] as an opaque string.

    {2 The fee is authority, not a number}

    [granter] and [payer] name accounts other than the signer that will be
    charged. A signer shown "fee: 1000uatom" and not shown a granter has been
    told the cost and not told who bears it, which is the more interesting half.
    Both are surfaced, and both are [None] when the field is empty rather than
    being rendered as an empty address.

    {2 Public keys}

    A secp256k1 key is parsed. Anything else — ed25519, a multisig threshold
    key, an app-chain's own scheme — is kept opaque and named, because a key
    this library cannot parse is a signer it cannot attribute. *)

module Address = Cosmos_types.Address
module Coin = Cosmos_types.Coin

type sign_mode =
  | Direct
  | Legacy_amino_json
  | Other of int
      (** Including [SIGN_MODE_DIRECT_AUX] and [SIGN_MODE_EIP_191]. Not
          [SIGN_MODE_TEXTUAL]: cosmos-sdk v0.55.0 reserved that number and
          withdrew the name. *)

type public_key =
  | Secp256k1 of Cosmos_crypto.public_key
  | Other_key of { type_url : string; value : string }

type signer = {
  public_key : public_key option;
      (** [None] where the account's key is already known to the chain and the
          transaction omits it, which is legal. *)
  mode : sign_mode;
  sequence : int64;
}

type fee = {
  amount : Coin.t list;
  gas_limit : int64;
  payer : Address.t option;
  granter : Address.t option;
}

type t

val make : signers:signer list -> fee:fee -> (t, string) result
val of_bytes : base:string -> string -> (t, string) result

val to_bytes : t -> string
(** The kept bytes. *)

val signers : t -> signer list
val fee : t -> fee

val has_fee_delegation : t -> bool
(** [true] if a payer or granter other than the signer is named. The question a
    policy should ask before it looks at the amount. *)
