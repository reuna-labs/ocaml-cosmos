# Release

Status: **public alpha train; the next candidate remains unaudited.**

`v0.1.0-alpha2` and its complete dependency closure are installable without
credentials from the public Reuna opam overlay. The private-dependency blocker
that shaped the original release plan is closed: immutable source tags,
archive checksums, and the exact first-release roots are recorded in the
overlay's `release/first-release.lock`.

## Publishing order

Dependency order remains risk order:

1. `web3-codec-bech32`, `web3-codec-protobuf`.
2. `cosmos-proto`, regenerated from the protocol pin and diffed.
3. `cosmos-types`, `cosmos-crypto`.
4. `cosmos-tx` and `cosmos-signer`, with both conformance oracles green.
5. `cosmos-rpc`, then its flow, gRPC, and Unix transports.
6. `cosmos`, the umbrella package.

For a new Cosmos release:

1. settle the source commit and run ordinary CI;
2. run and inspect all six sustained-fuzz artifacts for that code baseline;
3. create the immutable source tag and GitHub release;
4. import every `cosmos*.opam` file with the overlay's
   `tools/import-release.sh`;
5. replace the Cosmos root row in `release/first-release.lock` with the new
   tag, archive URL, and SHA-256/SHA-512 values;
6. run `tools/check.sh`, publish the overlay commit, and require the complete
   three-compiler install/consumer matrix to pass.

Never update a checksum at an existing tag. A changed archive or package set
requires a new tag.

## Assurance gates

The alpha line requires L0–L5 green and L6 in progress:

- public unauthenticated installation from checksum-pinned archives;
- conformance fixtures reproduced by protoc, the Go SDK, and CosmJS;
- `test/no_io_guard.sh` and the Solo5/flow link proofs clean;
- guarded testnet construction, simulation, broadcast, and confirmation;
- bounded fuzz targets kept green in ordinary CI;
- a retained sustained AFL campaign on parsers and submission state;
- independent review of signing bytes, intent/policy derivation, Amino
  canonicalization, and sequence recovery.

The maintainer pre-review and independent-review brief are in
`docs/pre-review-2026-09-01.md` and `docs/security-review.md`. They do not close
the independent-review gate. Every package remains labeled **public, unaudited
alpha**, and must not control assets of value.
