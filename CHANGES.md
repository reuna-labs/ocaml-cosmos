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

### L1, in progress

- **Prefixes and addresses.** Reading the pinned Go source rather than working
  from memory changed three rules. Bech32 decoding uses a 1023-character limit,
  not BIP-173's 90 (`types/bech32/bech32.go:21`). An address is any 1 to 255
  bytes — `VerifyAddressFormat` does not require 20 or 32, and the SDK's own
  tests round-trip a ten-byte address — so `of_bytes` decodes what the chain
  accepts and `is_standard_length` is what a policy asks. Encoding pads the
  8-to-5 bit conversion and decoding must not. Vectors are the SDK's own
  literals.
- **Amounts.** A fixed 256-bit unsigned integer, sixteen 16-bit limbs, no
  bignum: `math.Int` is capped at 256 bits and 64 is not enough for an
  eighteen-decimal token. Every operation that can leave the range returns
  `Error`; nothing wraps. Checked against Python's arbitrary-precision
  integers.
- **Denominations and coins.** The SDK's denom regular expression, matched by
  hand so the closure needs no regular-expression library. Coins deliberately
  do not add.
- **secp256k1.** Signing over a caller-supplied 32-byte digest, RFC 6979
  deterministic, normalised to low-S — which the SDK's verifier requires before
  it checks anything else (`secp256k1_nocgo.go:43-51`). Normalisation uses
  `Primitive.scalar_negate`, constant time and needing no bignum, rather than
  the arbitrary-precision arithmetic `ocaml-tron` does it with. Addresses are
  `RIPEMD160(SHA256(compressed pubkey))`.

  The vectors come from `conformance/oracle/secp256k1.py`, a complete
  independent implementation written for the purpose. One of them predates both:
  private key 1 derives hash160 `751e76e8…`, the witness program in BIP-173's
  own SegWit example.

- **Fixed-point decimals, chain ids and profiles.** `LegacyDec` is eighteen
  decimal places (`math/legacy_dec.go:20-21`) and reaches the wire as the
  integer scaled by 10^18, not as the human spelling — both are constructible
  and neither is called `of_string` alone. The one arithmetic operation is
  `mul_ceil`, because the one thing a signer computes is a fee, and rounding a
  fee down produces a transaction the node refuses for being a base unit
  short. Chain ids are 1..50 characters (CometBFT `types/genesis.go:20`) and
  are a type because they are inside `SignDoc`.

  A chain is a record, never a branch: prefix, chain id, fee denomination,
  exponent and minimum gas price are all that differ across the ecosystem.
  Six profiles are committed for testing and examples, all built through the
  validating constructor, and they are explicitly not authoritative — gas
  prices are governance parameters.

### Not done

L2 onwards. Nothing here builds a transaction yet.
