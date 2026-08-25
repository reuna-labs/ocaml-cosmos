# The Go SDK oracle

Runs cosmos-sdk v0.55.0's own encoders over the transaction
`conformance/protoc/*.txtpb` describes, and writes what it serialises to.

```sh
conformance/simd/generate.sh
git diff --exit-code conformance/fixtures/
```

It answers two questions, and only the second needs it.

## The protobuf encoding

Overlaps with `protoc` deliberately. `split.py` compares the two and fails if
they disagree — two independent oracles agreeing on the same bytes is worth
more than either alone, and a disagreement would be the finding rather than
something to reconcile quietly. They currently agree on all seven encodings.

## Amino JSON, which nothing else supplies

`SIGN_MODE_LEGACY_AMINO_JSON` cannot be derived from the schema. The `amino.*`
options govern it and interact with key ordering and number spelling in ways a
careful reading does not reveal. Three rules were established here and would
otherwise have been guessed wrong:

- `timeout_height` appears at the **top level** of the signed document, beside
  `memo` and `sequence`, as well as inside the body.
- CosmWasm's `msg` carries `(amino.encoding) = "inline_json"`, so the contract
  call is spliced in as JSON — and **re-serialised**, which sorts its keys. A
  call written `{"recipient":…,"amount":…}` signs as
  `{"amount":…,"recipient":…}`. A signer passing the caller's bytes through
  unchanged signs bytes the node does not compute.
- `(amino.dont_omitempty)` keeps `MsgSend.amount`, `MsgMultiSend.inputs` and
  `outputs`, `MsgTransfer.token` and `timeout_height`, and `Coin.amount` when
  they are empty, where the fields around them drop out.

### `x/tx/signing/aminojson`, not `legacytx.StdSignBytes`

`StdSignBytes` is deprecated upstream and drives the encoding from Go struct
tags rather than from the schema options. The two can disagree, and a
v0.50-and-later node verifies against the former. It also now panics unless a
codec is registered, which is upstream saying the same thing.

## Two things that bite when building this

`ibc-go` v10 requires an SDK too old for v0.55 — it asks for
`github.com/cosmos/cosmos-sdk/x/params`, which has moved to `cosmossdk.io`.
Use v11, which is the pin anyway.

Importing `cosmossdk.io/x/tx` alongside the SDK panics at init with
`proto: file "aminojsonpb/aminojson.proto" is already registered`: v0.55
vendored that package into itself. Import
`github.com/cosmos/cosmos-sdk/x/tx/...` instead.

## Everything is offline

No network, no node, no keys that control anything. The account number,
sequence, fee, timeout and addresses are constants matching
`conformance/protoc/*.txtpb`, so a mismatch is a disagreement about encoding
rather than about who called a node.

The first run downloads the SDK; after that `GOFLAGS=-mod=mod go run .` needs
nothing. The built binary is gitignored — it is 100MB.
