# Release

Status: **nothing has been released.** This file records the order and the
gates, not a procedure that has been run.

## The blocker

`cosmos.opam.template` names six pinned dependencies that live in private
`reuna-labs` repositories. Until that block is empty, a clean unauthenticated
machine cannot install this package, which is the G0 launch gate in
`vault/Reuna/Attic/OCaml web3 state of the art status.md`. Publishing anything
before that is publishing something nobody can install.

### What it looks like in practice

The runner has no git credential for github.com, so `opam pin` on any of the
six private dependencies fails with

```
fatal: could not read Username for 'https://github.com': No such device or address
```

CI therefore checks for a `REUNA_CI_TOKEN` repository secret before it does
anything else, and skips the build when it is absent rather than spending
thirty-five minutes building a compiler on the way to a failure it could have
predicted.

The `conformance` job needs nothing private and runs either way — the pin
check, protoc, the Go SDK and CosmJS. That is the payoff for keeping the
conformance inputs outside the fork closure: the thing most likely to catch a
protocol regression is also the thing that still works when the credential is
missing.

Adding the token makes the build run. It does not close G0: a token is how
*this* organisation reaches its own forks, and the gate is that an
unauthenticated clean machine can install the package at all. Closing it means
upstreaming `Mirage_crypto_ec.P256k1` and the digestif changes, or publishing
the forks, or vendoring them with provenance — the same choice
`ocaml-solana` faced and answered for the codec packages by vendoring a
snapshot at `vendor/web3-codec`. That answer does not transfer here unchanged:
Solana needs Ed25519, which released mirage-crypto-ec has, while this needs
secp256k1, which it does not.

## Order

Dependency order, which is also risk order:

1. `web3-codec-bech32`, `web3-codec-protobuf` — from `../ocaml-web3-codec`.
2. `cosmos-proto` — generated, and the easiest to verify: regenerate from the
   pin and diff.
3. `cosmos-types`, `cosmos-crypto` — the first packages that can be wrong in a
   way that costs money.
4. `cosmos-tx` — the signing boundary. Nothing here ships without the
   conformance fixtures green against both oracles.
5. `cosmos-rpc`, then the three transports.
6. `cosmos` — the umbrella, last, because it pins the others.

## Gates, per the launch document's L0–L6

An alpha release requires L0–L5 green and L6 in progress. In particular:

- both conformance oracles reproduce the committed fixtures in CI;
- `test/no_io_guard.sh` clean, including the GMP rule;
- a Solo5 guest that boots and signs;
- a sustained clean fuzzing run on the parsers and both state machines;
- `docs/threat-model.md` promoted from draft;
- independent review of the signing boundary, the intent derivation and the
  sequence handling.

Until then every package carries the alpha warning in `README.md` and
`SECURITY.md`, and the version stays `0.1.0~alpha1`.
