# Fuzzing

Status: **targets implemented and running bounded in CI**. No sustained AFL
campaign has completed yet, so this is maintenance evidence rather than the
L6 campaign gate.

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
| `fuzz_sign_doc` | arbitrary bytes | decoding is total; normalized encoding preserves every signed field and is idempotent; the digest covers those normalized bytes |
| `fuzz_amino` | generated messages | the canonical JSON writer is deterministic and key-sorted for every input |
| `fuzz_json` | arbitrary strings | CometBFT JSON-RPC response decoding never raises |
| `fuzz_submission` | generated response sequences | the submission state machine terminates, and never emits a signature over bytes it did not rebuild |

The last one matters more than it looks: the state machine is where sequence
handling lives, and a bug there is a replay or a stalled account rather than a
crash.

## Running

A real campaign needs an AFL-instrumented switch, which `reuna-5.5` is not and
must not become. Build and run it only through the dedicated campaign tooling;
never add AFL options to the shared switch.

The scheduled GitHub workflow runs all six targets in parallel for one hour
each on Linux and retains the resulting corpus, crashes, hangs, and AFL
statistics for 30 days. A manual run may select a different duration. Campaign
evidence is the workflow run plus its six artifacts; merely having the workflow
configured does not satisfy the sustained-campaign gate.

For a local campaign, create a separate switch containing
`ocaml-variants.5.5.0+options` and `ocaml-option-afl`, install the package's test
dependencies in it, install AFL++, and run:

```sh
COSMOS_AFL_SWITCH=cosmos-afl FUZZ_SECONDS=3600 \
  tools/run-fuzz-campaign.sh
```

Pass one target name to run only that target. `FUZZ_OUTPUT_ROOT` controls where
the corpus and findings are retained. Some macOS hosts have System V shared
memory limits below AFL++'s requirements; use the Linux workflow instead of
changing host kernel limits solely for this campaign.

The same targets run as bounded randomized executables in ordinary CI. This
keeps them compiling and catches regressions quickly, but it does not satisfy
the sustained-campaign gate.
