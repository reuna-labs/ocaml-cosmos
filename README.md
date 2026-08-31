# ocaml-cosmos

Cosmos SDK chains for OCaml: the pinned protobuf wire types, bech32 accounts,
`SIGN_MODE_DIRECT` and legacy Amino JSON, bank / IBC / CosmWasm transaction
construction with a byte-derived intent layer, and a typed client that reaches
a node over CometBFT JSON-RPC or gRPC without changing implementation between a
Unix socket and a Solo5 vsock.

> **Public, unaudited alpha software.** `v0.1.0-alpha2` contains the complete
> first signer/client slice, but it has not had sustained fuzzing or independent
> review. Do not use it to control assets of value. See `SECURITY.md` and the
> G10 milestones in
> `../vault/Reuna/Attic/OCaml web3 state of the art status.md`.

## Install

```sh
opam repository add reuna https://github.com/reuna-labs/opam-repository.git
opam update
opam install cosmos-rpc-unix.0.1.0~alpha2
```

This installs the hosted client and its pure transaction, signer, protobuf and
flow packages from checksum-pinned public release archives. No development pins
are required.

## Why a separate repository from `ocaml-cometbft`

They are the two halves of a Cosmos chain and they do not overlap.

`ocaml-cometbft` implements **ABCI 2.0** — the interface a consensus node uses
to talk to the state machine it replicates. It is what you use to *write a
chain* in OCaml.

`ocaml-cosmos` is the **client and signer** — the transaction envelope, the
sign modes, the addresses, the queries and the broadcast. It is what you use to
*hold an account* on someone else's chain.

Nothing in the first supplies any part of the second. They share a protobuf
runtime and a vendored `tendermint/*` schema, and that is the whole overlap.

## One envelope, many chains

The Hub, Osmosis, Celestia, Injective, dYdX, Neutron, Noble and roughly a
hundred app-chains sign the same `cosmos.tx.v1beta1` structure. What differs is
which messages they carry, what denomination they price gas in, and which
bech32 prefix they spell addresses with — so the chain is a *profile*, a record
of data, and never a branch in the code.

## What it does

- **Addresses.** 20 or 32 raw bytes plus a prefix; the bech32 spelling is a
  rendering. `cosmos1…` and `cosmosvaloper1…` are the same bytes and are not
  interchangeable, so the prefix is part of the type.
- **Signing.** secp256k1 over `SHA-256(SignDoc)`, 64 bytes, low-S, no recovery
  byte — the public key travels in `SignerInfo`. Deterministic (RFC 6979).
- **Two sign modes.** `SIGN_MODE_DIRECT` and `SIGN_MODE_LEGACY_AMINO_JSON`.
- **Transactions.** `MsgSend`, `MsgMultiSend`, IBC `MsgTransfer`, CosmWasm
  `MsgExecuteContract`. Built locally — never by the node.
- **Intent.** A reviewable meaning derived from the bytes about to be signed,
  with chain id, account number, sequence, fee, gas, granter, payer, memo and
  timeout as first-class fields, and allow-list policies over it.
- **Client.** CometBFT JSON-RPC and the SDK gRPC services, gas simulation, a
  confirmation state that is tagged rather than boolean, and a submission state
  machine in which a failure returns to account discovery rather than guessing
  at the sequence.
- **Two transports, one set of types**, both functorised over `Mirage_flow.S`
  so either reaches a Solo5 vsock.

## What it does not do

Deliberately, and each is a decision rather than an omission:

- **Chain state machines or SDK modules.** That is `ocaml-cometbft`.
- **Unrecognised messages.** Every message is a `google.protobuf.Any`. Four
  `type_url` values are on the allow-list; everything else decodes as opaque,
  can be displayed, and can never satisfy a policy.
- **Verifying what the node says.** That needs a light client and ICS-23
  proofs, and neither is in scope. A caller that needs proof of balance cannot
  get it here.
- **Relaying IBC.** This can tell you a transfer was delivered on the sending
  chain. It cannot tell you it arrived.
- **`SIGN_MODE_TEXTUAL`.** Withdrawn upstream in cosmos-sdk v0.55.0.
- **Reading a clock, or drawing randomness.** Neither happens anywhere in
  `lib/`. Timeouts are inputs; nonces are deterministic.

## Layout

```
lib/proto/          generated protobuf, committed, from proto/ @ the pins below
lib/proto/stubs/    hand-written empty modules for options-only imports
lib/types/          addresses and prefixes, coins, denoms, chain ids, profiles
lib/crypto/         secp256k1 signing, low-S, address derivation
lib/tx/             body, auth info, sign doc, amino JSON, messages, intent
lib/rpc/            the method catalogue, fees, confirmation, submission
lib/rpc_flow/       CometBFT JSON-RPC over any Mirage_flow.S -- incl. vsock
lib/rpc_grpc/       the SDK gRPC services over the same flow signature
lib/rpc_unix/       the flow functor, applied to a Unix file descriptor
lib/umbrella/       the offline surface, with no transport in its closure

proto/              the pinned .proto tree, closed under imports
conformance/        two independent oracles and their golden fixtures
validation/solo5/   the link proof: offline closure, no transport, no GMP
fuzz/               Crowbar targets for the parsers and state machines
docs/               the specification pin, the switch, the unikernel state,
                    the threat model, fuzzing and release
```

## Package boundaries

`cosmos-types`, `cosmos-crypto`, `cosmos-proto`, `cosmos-tx` and `cosmos-rpc`
are offline: no Unix, no Lwt, no clock, no RNG, no transport — and no `zarith`,
and therefore no GMP. `cosmos-rpc-flow` and `cosmos-rpc-grpc` own a socket and
may assume neither a host operating system nor a TCP stack. `cosmos-rpc-unix`
is the deliberate exception. `test/no_io_guard.sh` checks all of that from the
declared dependencies rather than by grepping sources.

The GMP-free property is worth a sentence because it is unusual: `ocaml-tron`
cannot make the same claim, since Base58 and public-key recovery both need a
bignum. Cosmos needs neither.

## Building

```sh
OPAMSWITCH=reuna-5.5 dune build @install
OPAMSWITCH=reuna-5.5 dune runtest
OPAMSWITCH=reuna-5.5 opam exec -- ./test/no_io_guard.sh
```

Read `docs/switch.md` first. `reuna-5.5` is the opam global default and is
shared with nethsm's confidential unikernel builds, so changes to it must be
additive.

## Pins

`cosmos-sdk` v0.55.0, `ibc-go` v11.2.0, `wasmd` v0.70.3, and the extension and
well-known-type schemas the three of them import. Every file is listed with its
sha256 in `docs/protocol-pin.md`, and `tools/fetch-proto.sh` reproduces the
tree.
