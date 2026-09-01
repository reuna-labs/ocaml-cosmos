# Independent security review brief

Status: **ready to commission; no independent review has been performed.**

This brief defines a bounded review rather than describing an assurance result.
The code baseline is commit
`0d3c8c69d526722f7e75a8ea001f86e5f8130cd9`. Any code change made in response
to a finding must be reviewed as a separate, explicitly identified delta.

## Objective

Determine whether an adversarial intent submitter or Cosmos node can cause the
library to approve, sign, broadcast, or report a transaction other than the one
the caller's policy accepted. Availability findings in parsers and transports
are also in scope because these components are intended to run inside a
long-lived confidential signer.

## Primary scope

Review these areas in risk order:

1. `lib/signer/`: request binding, freshness boundary, byte-to-intent review,
   Direct/Amino signed-byte selection, approval evidence, and secp256k1 use.
2. `lib/tx/`: retention of wire bytes, `Any` allow-list behavior, intent
   derivation, fail-closed policy review, Amino canonicalization, and framing of
   `SignDoc` and `TxRaw`.
3. `lib/rpc/submission.ml` and `lib/rpc/confirmation.ml`: sequence recovery,
   ambiguous broadcast outcomes, polling bounds, and terminal-state behavior.
4. Every decoder reachable from node-controlled bytes in `lib/rpc/`,
   `lib/rpc_flow/`, and `lib/rpc_grpc/`, including body-size bounds and
   exception containment.
5. `lib/crypto/` and the exact forked crypto/codec dependency closure named in
   the opam files and CI pins. In particular, verify the secp256k1 and protobuf
   changes rather than assuming their upstream projects contain them.

Generated files under `lib/proto/gen/` need not receive line-by-line review,
but their pinned inputs, generator/runtime boundary, and all reachable reader
behavior are in scope.

## Security invariants to challenge

- Intent and human rendering are derived from the exact inner bytes covered by
  the signature; builder inputs are not trusted as a description.
- A decoded `TxBody`, `AuthInfo`, or `TxRaw` is never silently re-encoded where
  protobuf's non-canonical encodings could change signed bytes.
- Unknown, malformed, multi-signer, extension-bearing, IBC, multi-send, and
  opaque CosmWasm semantics fail closed wherever the launch policy cannot
  explain them.
- Direct and legacy Amino modes cannot be confused or substituted, including
  edge cases in inline CosmWasm JSON canonicalization.
- Chain id, account number, sequence, fees, gas, signer count, memo, replay
  bounds, and delegation fields are all represented in the reviewed intent.
- Only caller-supplied signed bytes can reach broadcast, and an ambiguous
  broadcast never causes local sequence guessing or signing-byte reuse.
- Completion is absorbing: no late or reordered event changes a delivered,
  rejected, or gave-up result.
- Node-controlled JSON, protobuf, HTTP, and gRPC input is size-bounded where
  applicable and returns an error rather than escaping through an exception or
  memory-safety failure.
- TLS uses platform trust roots and authenticates the requested DNS name unless
  the caller deliberately supplies an authenticator.
- The offline package closure contains no socket, clock, RNG, Unix dependency,
  or GMP-backed arithmetic.

## Explicit trust boundaries and exclusions

The library does not verify consensus, account state, balances, inclusion
proofs, IBC delivery, or CosmWasm contract semantics. Nonce persistence,
attestation, trusted time, key custody, UI integrity, and authorization policy
selection belong to the embedding signer. Those boundaries should still be
checked for accidental claims or APIs that make unsafe integration likely.

Operational security of public RPC providers and testnet faucets is outside
the code review. Testnet evidence demonstrates interoperability, not mainnet
safety.

## Reproduction and evidence

Use a clean, unauthenticated machine and the public Reuna opam overlay. At the
baseline commit:

```sh
opam install --deps-only --with-test .
dune build @install
dune runtest
./test/no_io_guard.sh
dune build fuzz/
for target in _build/default/fuzz/*.exe; do "$target"; done
```

`docs/protocol-pin.md`, `conformance/`, `docs/fuzzing.md`, and the GitHub Actions
runs are the reproducibility evidence. A bounded Crowbar pass is not a
sustained fuzz campaign; campaign evidence must identify the workflow run and
retain all six AFL artifacts.

## Requested deliverables

The reviewer should provide:

- findings with severity, exploit prerequisites, affected bytes/state, and a
  minimal reproducer;
- a pass/fail assessment for each invariant above;
- dependency and generator/runtime findings separated from repository-local
  findings;
- a list of reviewed commits and tools, including fuzz duration and corpus;
- confirmation of organizational independence and any conflicts of interest;
- verification of each remediation against its exact follow-up commit.

Until that work is complete, repository documentation must continue to say
**public, unaudited alpha**.
