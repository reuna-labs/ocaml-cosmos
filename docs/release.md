# Release

Status: **nothing has been released.** This file records the order and the
gates, not a procedure that has been run.

## The blocker

`cosmos.opam.template` names six pinned dependencies that live in private
`reuna-labs` repositories. Until that block is empty, a clean unauthenticated
machine cannot install this package, which is the G0 launch gate in
`vault/Reuna/Attic/OCaml web3 state of the art status.md`. Publishing anything
before that is publishing something nobody can install.

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
