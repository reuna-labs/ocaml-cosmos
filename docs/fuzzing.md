# Fuzzing

Status: **not started**. `fuzz/` is empty; this file records what belongs in it
and why, so that the targets are not chosen by whatever is easiest to write.

## Why this is not optional here

Every byte this library parses came from a node it does not trust, and one of
those parsers has already been the site of a real memory-safety bug. Fuzzing
`ocaml-tron` found a **segfault in `ocaml-protoc-plugin`'s reader**, reachable
from 85 bytes of protobuf: an integer overflow in a bounds check let
`String.unsafe_blit` read past the buffer. It is fixed in the vendored runtime
in `ocaml-web3-codec`, which this repository depends on, and the details are in
that package's `lib/protobuf/README.md`.

The lesson worth carrying is that no caller-side guard would have helped. A
segfault is not an exception, so neither `Result.catch` nor a `try` around
`from_proto` catches it. The only defence was finding it.

## Targets

| Target | Input | The property |
| --- | --- | --- |
| `fuzz_bech32` | arbitrary strings | never raises; decode∘encode is identity; a Bech32m checksum never passes as an account address |
| `fuzz_proto` | arbitrary bytes | decoding any `TxRaw`/`TxBody`/`Any` never raises and never segfaults |
| `fuzz_sign_doc` | arbitrary bytes | a decoded `SignDoc` re-frames to exactly its source bytes |
| `fuzz_amino` | generated messages | the canonical JSON writer is deterministic and key-sorted for every input |
| `fuzz_json` | arbitrary strings | CometBFT JSON-RPC response decoding never raises |
| `fuzz_submission` | generated response sequences | the submission state machine terminates, and never emits a signature over bytes it did not rebuild |

The last one matters more than it looks: the state machine is where sequence
handling lives, and a bug there is a replay or a stalled account rather than a
crash.

## Running

A real campaign needs an AFL-instrumented switch, which `reuna-5.5` is not and
must not become. Build the targets in a separate switch:

```sh
opam switch create cosmos-afl ocaml-variants.5.5.0+afl --no-switch
```

Crowbar targets also run as ordinary quickcheck under `dune runtest`, which is
worth having in CI even though it is not a campaign.
