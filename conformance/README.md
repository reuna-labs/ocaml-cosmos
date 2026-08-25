# Conformance fixtures

Golden values produced by two independent Cosmos implementations, offline, and
committed. Tests compare against these literals; they never compare
`ocaml-cosmos` against itself.

**Status: not written.** This file is the contract the fixtures have to meet,
recorded at scaffold time so the oracles are not chosen for convenience later.

| Generator | Language | Directory | Why this one |
| --- | --- | --- | --- |
| `@cosmjs/proto-signing` + `@cosmjs/stargate` | TypeScript | `cosmjs/` | What most of the ecosystem's wallets and front ends actually use |
| the Go SDK's `simd` CLI | Go | `simd/` | The reference implementation itself, and therefore the stronger evidence about what a node will accept |

Two, not one, because a single oracle only tells you that two implementations
agree — yours and its. Where these two disagree, the disagreement is the
finding, and it belongs in the test as an assertion rather than being resolved
by picking a favourite. `ocaml-tron/conformance/` does exactly this and is the
model.

## What has to be covered

Each message in the launch allow-list, in **both** sign modes, because they are
different canonical encodings of the same transaction and a library can easily
be right about one and wrong about the other:

| | `SIGN_MODE_DIRECT` | `SIGN_MODE_LEGACY_AMINO_JSON` |
| --- | --- | --- |
| `MsgSend` | ✓ | ✓ |
| `MsgMultiSend` | ✓ | ✓ |
| `MsgTransfer` (IBC) | ✓ | ✓ |
| `MsgExecuteContract` (wasm) | ✓ | ✓ |

For each: the serialized `body_bytes`, the serialized `auth_info_bytes`, the
serialized `SignDoc`, its SHA-256, the signature, and the final `TxRaw`. Not
just the last one — a fixture that only pins the outer bytes cannot say which
layer is wrong when it fails.

Plus the cases that are not about a happy path:

- a high-S signature, which must be rejected;
- a `type_url` outside the allow-list, which must decode as opaque and fail
  every policy;
- a `TxBody` whose protobuf encoding is valid but non-minimal, which must
  re-frame to exactly its source bytes rather than to a canonical re-encode;
- a `cosmosvaloper1…` address where an account address is expected.

## Everything is offline

Neither generator may touch a network. Both SDKs normally build transactions by
asking a node for the account number and sequence; none of that is used. The
transaction is assembled from fixed inputs and only the pure pieces are called
— protobuf serialization, the sign doc, amino JSON and signing. That is exactly
the boundary `ocaml-cosmos` implements, so a mismatch is a real disagreement
about the wire format rather than about who called the node.

Keys are the smallest secp256k1 scalars. They control nothing. The chain id,
account number, sequence, fee and timeout are constants — nothing here may read
a clock, in the generators any more than in `lib/`.

## Regenerating

CI runs both and diffs `conformance/fixtures/`. Any drift fails the build: a
generator that no longer reproduces the committed bytes means either the SDK
changed or we did, and neither is something to discover at release time.

The CI job that does this is **not in `.github/workflows/test.yml` yet**. It
was written and then removed, because guarding it on
`hashFiles('conformance/fixtures/**')` is not valid in a job-level `if` and
GitHub's response to that is to fail the whole workflow in zero seconds with
no log and no jobs — the workflow's name even shows as its path in the API,
which is the only visible symptom. Add the job back when there are fixtures
for it to check, unconditionally, rather than guarding it on their existence.
`ocaml-solana/.github/workflows/test.yml` has the shape to copy.
