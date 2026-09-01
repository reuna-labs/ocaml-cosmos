# Fuzzing

Status: **targets implemented, bounded in ordinary CI, and sustained campaign
completed**. The retained Linux campaign for commit
`9ab9a0e6b45a316cd1b6126cdd651f6f2e04090e` closes the Cosmos sustained-fuzz
portion of L6; independent review remains open.

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

## Retained campaign evidence

[Workflow run `33472105111`](https://github.com/reuna-labs/ocaml-cosmos/actions/runs/33472105111)
completed on 2026-09-01 at the exact commit above. Every target recorded
`run_time: 3600`; the six targets executed 33,597,760 cases in total. All six
`fuzzer_stats` files report zero saved crashes and zero saved hangs, and direct
inspection of every retained `crashes/` and `hangs/` directory found no finding
files.

| Target | Executions | Cycles | Retained corpus | Crashes | Hangs |
| --- | ---: | ---: | ---: | ---: | ---: |
| `fuzz_amino` | 4,944,533 | 140 | 171 | 0 | 0 |
| `fuzz_bech32` | 5,321,268 | 354 | 116 | 0 | 0 |
| `fuzz_json` | 5,968,063 | 137 | 241 | 0 | 0 |
| `fuzz_proto` | 5,747,028 | 19 | 728 | 0 | 0 |
| `fuzz_sign_doc` | 5,937,351 | 169 | 189 | 0 | 0 |
| `fuzz_submission` | 5,679,517 | 222 | 170 | 0 | 0 |

The inspected artifact archives have these SHA-256 digests:

| Target | Artifact SHA-256 |
| --- | --- |
| `fuzz_amino` | `5c738db02c92916865ac5325a7ae0dca135beb5dcba6189e2de12cdc8ca9447e` |
| `fuzz_bech32` | `f86818cc4eaa63c96965931cbf21bcd4ce6403545935c7b1a17daf6e160aff3e` |
| `fuzz_json` | `d130cfa5efa4a7713d07541276da805aac8ab98f3b5414f2ff40579f69dc0087` |
| `fuzz_proto` | `564a22657a853ee203fb3c9feb0c0ca58d073a6e2699081b88ce8d6da0d7d277` |
| `fuzz_sign_doc` | `2fef0bf242df35b38598025878f7207329d0e1d7d7691fa2e63ae78774de7a71` |
| `fuzz_submission` | `9cb2159f8d29bf131aa22f0e0d85bb8bb0c0729b5512ea65d5d62509b8e36637` |

GitHub-hosted runners pipe core dumps to an external collector and do not let
the job change `kernel.core_pattern`. The workflow uses AFL's documented hosted
runner override, which means a crash delayed by that collector may appear under
`hangs` rather than `crashes`; both directories are retained and must be
inspected. Local Linux campaigns should leave the override unset and configure
direct core handling instead.

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
