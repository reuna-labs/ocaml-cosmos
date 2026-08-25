# Changes

## 0.1.0~alpha1 (unreleased)

Repository scaffold and the L0 specification pin.

### Added

- **The pinned schema tree.** `proto/`, 40 files, closed under imports:
  `cosmos-sdk` v0.55.0, `ibc-go` v11.2.0, `wasmd` v0.70.3, and the
  `cosmos_proto`, `gogoproto`, `tendermint`, `google/api` and
  `google/protobuf` schemas they import. `tools/fetch-proto.sh` reproduces it
  by resolving imports recursively from a list of entry points;
  `docs/protocol-pin.md` records every file's sha256 and why each pin is what
  it is.
- **`cosmos-proto`.** 38 generated modules (34 schema, 4 well-known types),
  committed, built through the shared
  `../ocaml-web3-codec/tools/gen-protobuf.sh`. Compiles. Two further modules in
  `lib/proto/stubs/` are hand-written and deliberately empty: `google/api/*` is
  imported for its service options only, never appears on the wire, and one of
  its doc comments lists the HTTP verbs in a form OCaml reads as an
  unterminated string literal.
- **Nine packages** with their boundaries and dependencies fixed:
  `cosmos-proto`, `cosmos-types`, `cosmos-crypto`, `cosmos-tx`, `cosmos-rpc`,
  `cosmos-rpc-flow`, `cosmos-rpc-grpc`, `cosmos-rpc-unix`, `cosmos`. The
  module interfaces that carry a protocol rule — `Sign_doc`, `Msg`,
  `Amino_json`, `Prefix`, `Confirmation`, `Submission`, `Cosmos_crypto` — are
  written; the implementations are not.
- **`test/no_io_guard.sh`**, with the usual I/O rule and one this repository
  adds: no `zarith`, and therefore no GMP, anywhere in the offline closure.
- **`validation/solo5/`**, the link proof for that closure.
- **`docs/`** — the pin, the switch, the unikernel state, a draft threat model,
  the fuzzing plan and the release order.

### Changed, in `../ocaml-web3-codec`

- **`web3-codec-bech32`** sliced out of the `web3-codec` umbrella as a lean
  package with no dependencies at all, following `web3-codec-basen`,
  `-base58`, `-borsh` and `-cbor`. `Web3_codec.Bech32` still resolves, so this
  breaks nothing. `ocaml-cardano` carries a private copy for want of this
  package and can now drop it.
- `encode` and `decode` gained `?max_length`, defaulting to BIP-173's 90. The
  Cosmos SDK does not enforce that cap, so a decoder fixed at 90 cannot read a
  long-HRP app-chain address; raising it weakens the checksum guarantee, which
  is why it has to be said at the call site.
- `tools/gen-protobuf.sh` gained `-p`, which appends plugin parameters to the
  shared ones and applies them to the well-known types too. Cosmos needs
  `prefix_output_with_package=true` because it defines four `tx.proto`, three
  `keys.proto` and two `query.proto` in different packages; without it the
  plugin reports "Tried to write the same file twice" and emits nothing.
  Default is off, so no existing consumer changes.

### Not done

L1 onwards. Nothing here signs anything yet.
