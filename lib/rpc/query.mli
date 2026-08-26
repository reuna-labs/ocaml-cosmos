(** The typed queries a signer needs, over {!Method.abci_query}.

    Each one encodes a protobuf request, wraps it in an ABCI query, and decodes
    the protobuf response — so a caller never handles either encoding.

    {2 Why the account query is the important one}

    It carries [account_number] and [sequence], and both go inside the signed
    document. Neither can be guessed: the account number is assigned when the
    account is first funded, and the sequence is whatever the chain has counted
    so far. A signer that invented either would produce a transaction the chain
    rejects — or, worse, one it accepts as a replay of something else. *)

module Address = Cosmos_types.Address
module Coin = Cosmos_types.Coin
module Denom = Cosmos_types.Denom

type account = {
  address : Address.t;
  account_number : int64;
  sequence : int64;
  has_public_key : bool;
      (** [false] until the account has signed something. The chain learns the
          key from the first transaction, so a funded but unused account has
          none, and that is normal rather than a problem. *)
}

type account_result =
  | Base of account
  | Other of { type_url : string }
      (** A module account, a vesting account, or an app-chain's own type. Not
          decoded: a signer does not sign for one, and extracting an embedded
          sequence would be a claim about a type this library does not model. *)

val account : base:string -> Address.t -> account_result Method.t
(** A missing account is {!Error.Abci} with code 22 — the node answered, and
    there is nothing there. That is a different answer from a malformed request,
    which is code 18, and callers that treat them alike will retry one that will
    never succeed. *)

val balance : base:string -> Address.t -> denom:Denom.t -> Coin.t Method.t
(** A zero balance is a coin of zero, not an error. *)
