# ocaml-cosmos

Cosmos SDK chains for OCaml: the pinned protobuf wire types, bech32 accounts,
`SIGN_MODE_DIRECT` and legacy Amino JSON, bank / IBC / CosmWasm transaction
construction with a byte-derived intent layer, and a typed client that reaches
a node over CometBFT JSON-RPC or gRPC. Built to run as a MirageOS/Solo5
unikernel, not only as a Unix library.

**This is the client and signer side.** The application side of a Cosmos chain
— ABCI 2.0, the interface a consensus node uses to talk to the state machine it
replicates — is `../ocaml-cometbft`, and the two share nothing but a protobuf
runtime and a vendored `tendermint/*` schema. Neither is a substitute for the
other.

## Invariants

Signed-data libraries are deterministic and free of Unix, Lwt, environment,
clock, RNG and transport dependencies. `test/no_io_guard.sh` enforces this by
inspecting declared dependencies, not by grepping sources.

**The bytes that were signed are the bytes that go out.** `SignDoc` binds
`body_bytes` and `auth_info_bytes` as opaque byte strings and `TxRaw` carries
those same strings back out. They are retained, never re-encoded. Protobuf
admits encodings that decode alike and re-encode differently, so a re-encode
changes what the node is being asked to do — and here the signature covers a
concatenation of both, so it is load-bearing twice over. This is
`ocaml-tron`'s `Raw_data.of_bytes` rule.

**Unrecognised is not approvable.** Every message in a `TxBody` is a
`google.protobuf.Any`. The allow-list is `MsgSend`, `MsgMultiSend`, IBC
`MsgTransfer` and CosmWasm `MsgExecuteContract`; any other `type_url` decodes
as opaque, reaches the intent layer as opaque, and cannot satisfy a policy.
There are roughly a hundred Cosmos app-chains with custom modules, and a signer
that cannot explain one has no business approving it.

**Nothing here reads a clock.** `timeout_height` and `timeout_timestamp` bound
a transaction's validity. A signer that could fetch the current time could be
walked into widening its own window. The current time is an input.

**Nothing here draws randomness.** ECDSA nonces are RFC 6979 deterministic, so
no generator is needed and `mirage-crypto-rng` initialisation stays off a
unikernel's critical path.

**Signatures are low-S.** The SDK rejects high-S as malleable and
`mirage-crypto-ec` does not normalise, so this is a correctness requirement.
A signature that is right by every other measure and high-S is refused by the
node, which looks like a signing bug one layer up from where it is.

**No zarith, and therefore no GMP.** Unlike `ocaml-tron`, this closure needs
neither. Cosmos never recovers a public key from a signature — the key travels
in `SignerInfo` — so `mirage-crypto-blockchain`'s reference bignum backend is
not required; address derivation is RIPEMD-160 over SHA-256 from `digestif`,
the curve work is `mirage-crypto-ec`'s fiat-crypto P256k1, bech32 is integer
arithmetic and the protobuf runtime is `base64` + `ptime`. Losing this is
silent — the code still builds, the duniverse just stops locking — so
`test/no_io_guard.sh` checks it alongside the I/O rule.

**Both flow transports must reach a vsock.** `cosmos-rpc-flow` and
`cosmos-rpc-grpc` are functorised over a flow and may not depend on anything
that assumes a host operating system or a TCP stack. `cosmos-rpc-unix` is the
deliberate exception.

The signature they take is a minimal four-function `FLOW`, not `Mirage_flow.S`.
Its `write_error` is a private row type that will not functor cleanly onto a
concrete flow, and requiring `shutdown`, `close` and `writev` would demand what
these clients never call — and rule out a flow made of two in-memory buffers,
which is what `validation/flow/` uses to prove the claim. Every
`Mirage_flow.S` satisfies the smaller signature structurally.

Network tests are opt-in; ordinary `dune runtest` is hermetic.

### Three prefixes, one set of bytes

`cosmos1…`, `cosmosvaloper1…` and `cosmosvalcons1…` are the same 20 bytes under
different bech32 human-readable parts. Nothing in the encoding stops one being
read as another, so the prefix is part of the address type rather than part of
its formatting. See `lib/types/prefix.mli`.

### Two sign modes, and the second cannot simply be refused

`SIGN_MODE_DIRECT` is the product path. `SIGN_MODE_LEGACY_AMINO_JSON` is what
Ledger devices and several app-chain paths still require: a different canonical
encoding of the same transaction, with sorted keys, no whitespace, omitted
empty fields and amino type names that do not match the protobuf `type_url`. A
signer that cannot produce it cannot serve those callers; one that cannot
decode it cannot refuse it intelligibly.

`SIGN_MODE_TEXTUAL` is not implemented and will not be — cosmos-sdk v0.55.0
reserved field 2 and withdrew it. See `docs/protocol-pin.md`.

## Build switch

This repository builds in the shared **`reuna-5.5`** switch and carries no local
`_opam`. That switch is the opam global default and is shared with nethsm's
confidential unikernel builds, so changes to it must be additive.
**Read `docs/switch.md` before running any opam command here.**

Regenerating the protobuf bindings uses a second switch, `web3-protoc`.
Generated sources are committed, so an ordinary build never touches it.

## Where this repo sits

`~/reuna/web3/ocaml-cosmos` — the `web3/` group (OCaml/Mirage web3 protocol libraries).

The tree was reorganised into effort groups; peer repositories are **no longer siblings**
at `../`. The full layout:

- `~/reuna/web3/` — OCaml/Mirage web3 protocol libraries
- `~/reuna/ports/` — Solo5 enclave core, language runtime ports and samples
- `~/reuna/ha/` — Reuna HA components
- `~/reuna/trust/` — Reuna trust components and the signed wire contracts
- `~/reuna/platform/` — RTP and the Kubernetes admission/runtime surface
- `~/reuna/research/` — reference checkouts, studied not built
- `~/reuna/vault/Reuna/` — the Obsidian design vault (Strategy, HLD, `SDD/`). Reachable from any group as `../vault/Reuna/` via a symlink.
- root also holds `infra/`, `release/`, `knowledge-bundle/`, `demo-app/`, `drivers/`, `attic/`

## Direct peers

| Repository | Path | Why |
| --- | --- | --- |
| `ocaml-web3-codec` | `../ocaml-web3-codec` | `web3-codec-protobuf` (the vendored `ocaml-protoc-plugin` runtime and the shared generator invocation), `web3-codec-bech32` (sliced out of the umbrella for this repository) |
| `ocaml-cometbft` | `../ocaml-cometbft` | Not a build dependency. It is the other side of ABCI, and the reason this repository exists as a separate thing. Its `proto/tendermint/**` tree is the same schema vendored here. |
| `ocaml-tron` | `../ocaml-tron` | Not a build dependency. It is the structural template: protobuf chain, flow-functorised HTTP and gRPC, `no_io_guard.sh`, two conformance oracles. Read its `lib/rpc_grpc/io_of_flow.ml` before writing this one's. |
| `mirage-crypto` fork | `../../ports/ocaml/mirage-crypto` | `Mirage_crypto_ec.P256k1`, a fork addition not yet upstream |
| `digestif` fork | `../../ports/ocaml/digestif` | SHA-256 and RIPEMD-160 |

In the `reuna-5.5` switch the build dependencies are already pinned; see
`docs/switch.md`.

## Design docs

- `../vault/Reuna/SDD/` — component design documents
- `../vault/Reuna/Platryx HLD.md` — how the components fit together

## Helper toolkits — `~/gilbahat`

Peer repositories used as tooling live **outside** `~/reuna`, in `~/gilbahat`. They are not
checked out here and are referenced by absolute path:

- `~/gilbahat/qemu` — patched QEMU (the tree the enclave/emulation scripts invoke)
- `~/gilbahat/qemurb`, `~/gilbahat/vhost-device`, `~/gilbahat/vsock-emulation-layer` — virtio/vsock plumbing for macOS-hosted guests
- `~/gilbahat/confidential-computing.sgx` — patched SGX emulation
- `~/gilbahat/ms-tpm-20-ref` — TPM simulator; `tpm2-tss`, `tpm2-tools`, `tpm2-pkcs11`, `tpm2-abrmd`, `tpm2-pytss` — mac-friendly TPM library builds
- `~/gilbahat/ocaml-tpm2` — OCaml ESAPI bindings (`OCAML_TPM2_DIR`)
- `~/gilbahat/elfuse` — ELF/FUSE tooling
- `~/gilbahat/alloy`, `~/gilbahat/opentelemetry-collector` — telemetry
- `~/gilbahat/aws-nitro-enclaves-cli` — Nitro tooling
- `~/gilbahat/karpenter`, `karpenter-provider-{aws,azure,oci}` — cluster autoscaling
- `~/gilbahat/ding-libs`, `~/gilbahat/libverto` — gssproxy build dependencies

Prefer the existing env-var knobs where a script defines one (`SGX_PATCHED_SOURCE`,
`VSOCK_EMULATION_LAYER`, `OCAML_TPM2_DIR`, `SIM`) rather than hardcoding a new path.
