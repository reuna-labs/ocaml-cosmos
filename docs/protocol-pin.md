# Specification pin (L0)

Every wire format this library implements is pinned to an exact upstream
revision here. Nothing in `lib/` may encode a rule that is not traceable to a
line in this document.

Cosmos has no single schema repository, and that is the first thing to
understand about it. The transaction envelope belongs to `cosmos-sdk`, IBC to
`ibc-go`, CosmWasm to `wasmd`, and all three import extension definitions from
three further repositories. `proto/` is the closure of all of them: `protoc -I
./proto` needs nothing else on the machine, including no `protoc` include path,
because the well-known types are vendored too.

## Sources

| Namespace | Repository | Pin | Dated |
| --- | --- | --- | --- |
| `cosmos/`, `amino/` | [`cosmos/cosmos-sdk`](https://github.com/cosmos/cosmos-sdk) | v0.55.0 `64fd208a11fb` | 2026-07-28 |
| `ibc/` | [`cosmos/ibc-go`](https://github.com/cosmos/ibc-go) | v11.2.0 `cfc072e53eee` | 2026-07-15 |
| `cosmwasm/` | [`CosmWasm/wasmd`](https://github.com/CosmWasm/wasmd) | v0.70.3 | 2026-06-24 |
| `cosmos_proto/` | [`cosmos/cosmos-proto`](https://github.com/cosmos/cosmos-proto) | `3e53812559a5` | 2024-06-25 |
| `gogoproto/` | [`cosmos/gogoproto`](https://github.com/cosmos/gogoproto) | `fc9edf209aa4` | 2026-08-24 |
| `tendermint/` | [`cometbft/cometbft`](https://github.com/cometbft/cometbft) | v0.38.17 | — |
| `google/api/` | [`googleapis/googleapis`](https://github.com/googleapis/googleapis) | `2e9c5681901a` | — |
| `google/protobuf/` | [`protocolbuffers/protobuf`](https://github.com/protocolbuffers/protobuf) | v32.0 | — |

### Why these, and not the newest of everything

`cosmos-sdk` `v0.55.0` is the newest release, and the envelope in it is
byte-identical to the one in `v0.53.8` apart from two corrected typos in
comments — the diff between the two `cosmos/tx/v1beta1/tx.proto` files is
exactly those two lines. That is the evidence behind the claim that the
envelope is wire-stable across `v0.50`–`v0.55`, and it is why a client pinned
here talks to older chains without a second schema.

One substantive change did land in `v0.55.0`, in
`cosmos/tx/signing/v1beta1/signing.proto`:

```
+  reserved 2;
+  reserved "SIGN_MODE_TEXTUAL";
-  SIGN_MODE_TEXTUAL = 2;
```

`SIGN_MODE_TEXTUAL` has been withdrawn. This library implements
`SIGN_MODE_DIRECT` and `SIGN_MODE_LEGACY_AMINO_JSON` and does not implement
textual, which the pin now makes a statement of fact rather than a scope
decision.

`googleapis` has no release tags, so it is pinned to a commit. Tracking
`master` would make the fetch unreproducible, which matters even for files that
are only stubbed: an import that changes shape changes what the generated code
references.

`cometbft` is pinned on the `v0.38` line because that is where the
`tendermint/*` protobuf namespace lives; later CometBFT releases renamed it to
`cometbft/*`. The Cosmos `v0.55.0` protos still import `tendermint/*`, so the
pin follows the importer, not the newest tag.

`google/protobuf/*` is vendored rather than taken from `protoc`'s builtin
include path, so that the generated output does not silently depend on which
`protoc` happened to be installed. Generated with `libprotoc 36.0`.

`google/api/*` is vendored because the Cosmos service definitions import it,
and is **not** generated — see `lib/proto/stubs/`.

## Vendored files

Every file below was fetched by `tools/fetch-proto.sh`, which resolves imports
recursively from the entry points listed in it. The tree is closed: nothing
here imports anything not here.

| File | sha256 |
| --- | --- |
| `amino/amino.proto` | `bc4cb71a5b49ce23e7b9ff8e5cd9f42efa9527c8f2d2e3861c901c7e86be202e` |
| `cosmos/auth/v1beta1/auth.proto` | `a2c13ee1c4461ee072b5574c4c551013e9885fd16ca54450f3213b5303f1f4a1` |
| `cosmos/auth/v1beta1/query.proto` | `561be76e5bdfb9d2f043884adef33ef102c71dc9911cff4c514cba5a1f834bc1` |
| `cosmos/bank/v1beta1/bank.proto` | `d36d05d8ae2e5b39dd0a182f9ad8599e712060100cb6f700cf7e28487bdd3dee` |
| `cosmos/bank/v1beta1/query.proto` | `c7bec81be1cb37cafe0e53187386e0cea66d3074ce3a33cba18209b17f71abfc` |
| `cosmos/bank/v1beta1/tx.proto` | `27bf0784683995dc7243cbcae67a3dd876cf7ad79295a8294c537a9683c4d2ac` |
| `cosmos/base/abci/v1beta1/abci.proto` | `90f099bd8a0e85edb3bfe07f79a640af2bdbf0d33a5995c370f0e46ee3ef49d2` |
| `cosmos/base/query/v1beta1/pagination.proto` | `8a878b43363c1fe2098e7b49b65fc5e5226daa13862d250848f4cf83007c8262` |
| `cosmos/base/v1beta1/coin.proto` | `38ea72ac8d68f74eca2d9afa116b6eea06e85f62882096bb53622fd139a3e2d3` |
| `cosmos/crypto/ed25519/keys.proto` | `cbeddc4af46ea4e12ef4a7b21e64fdd39de71f6bddad8e0896c1aba197c1447d` |
| `cosmos/crypto/multisig/keys.proto` | `001808515cb5e1b7cab85a02cadd0baed42d2912675deb8f2d1777667331e459` |
| `cosmos/crypto/multisig/v1beta1/multisig.proto` | `cd09151fe7b54db0d66331e786f762fa34423f1bd09b994696fa925432bd51ce` |
| `cosmos/crypto/secp256k1/keys.proto` | `d69386568e35c2c20cf367307489f9e50a2710a71552c531a20aee8d9371ba62` |
| `cosmos/msg/v1/msg.proto` | `4100c0021a143b5a273964f2472523d8e61fe28acaccade898f05becc3af8f31` |
| `cosmos/query/v1/query.proto` | `f0251d79e920ddeb91982024859b29230cd230de180ef895c41d0767bec01d1d` |
| `cosmos/tx/signing/v1beta1/signing.proto` | `129219d4730fdc7cc65fc10a258f9f47e1ac484a329ef3312c02b68370aa6bb4` |
| `cosmos/tx/v1beta1/service.proto` | `c589dc0ce0acf6470745f299be71ceba7191a36cab1acaf7dc7324397ff322d0` |
| `cosmos/tx/v1beta1/tx.proto` | `6d694815814303538b08e6bb01da889de5fed3c1b15cb504668741f1f36491e1` |
| `cosmos_proto/cosmos.proto` | `9104e7bc5b757cac81ecd2874b34ad650ff06091e1b68e21ec0b0d9d5c36606b` |
| `cosmwasm/wasm/v1/tx.proto` | `5de0e18ee4d35f9073e9fd17e5a10ae7cff70133fec25572ee9cea4fdf7519df` |
| `cosmwasm/wasm/v1/types.proto` | `5ddf80274cb94a2eb46f6f5cd70416bbc5eda160999cbcfafca8c129934b744f` |
| `gogoproto/gogo.proto` | `a2bef0fb7e233ff2f442da08b3764be6ce59cc3f2df05cd1c9a44dbb5b55c18f` |
| `google/api/annotations.proto` | `e79ea741cb605a65e78ca322174764a4af9fde1962c1631e12b84c4934ba9a6c` |
| `google/api/http.proto` | `ead99129aa15dd5f6233942030c72eec33bc0d7b1c7c260dc143293ef66c5b78` |
| `google/protobuf/any.proto` | `bcf5de6ce463b1a38ff76b77955aa7e580b4ec12af34a927b1d45c9efb0faf66` |
| `google/protobuf/descriptor.proto` | `061baf8f69810b981d5d33204e2665c8d3f255b902336f7f535d4bd8790e35ad` |
| `google/protobuf/duration.proto` | `a3f7301ff2956ec2e30c2241ece07197e4a86c752348d5607224819d4921c9fe` |
| `google/protobuf/timestamp.proto` | `14052c6042c1dd2d0b50245f2812eaab6eaf82db0b6e8ce483eae527f73b6ee8` |
| `ibc/applications/transfer/v1/transfer.proto` | `7e41fe5c2fa1014ef8e84256a30ede2409a411135c18a2834d88a79912032206` |
| `ibc/applications/transfer/v1/tx.proto` | `9ec0997b83f0e1ce021cef93e2bba27c231f0464dead4c73370b05fa5e728c54` |
| `ibc/core/client/v1/client.proto` | `0f081cea9e1fdaea4ebf1e35d02a66e5630844351943d05b0cdcce2f063b8469` |
| `tendermint/abci/types.proto` | `b0b78373a8f93c4f8a747367ba1a52f41e4d5e228ead24fe4ab71da600c33efd` |
| `tendermint/crypto/keys.proto` | `41021beae17901ad2360d1f1ab040d7d28adb89a784fba9935fcbed638e39bac` |
| `tendermint/crypto/proof.proto` | `926346f92322a8460753426c578e360c13cce5124d0d6e7245230c56b88613f7` |
| `tendermint/types/block.proto` | `fc7b552f52351ae2aa146efe628b16364cd1f41071fb2252dcf36e84e8e5f527` |
| `tendermint/types/evidence.proto` | `8075adcb2e76832e92ca04c2dbedaff3c601a4b9b28ba28428967b4338e8b9e0` |
| `tendermint/types/params.proto` | `d4141c7d3dcb7ef207f9e46bcbddb124a1ee68aa9ae32c7abc95a4e57bd32e1c` |
| `tendermint/types/types.proto` | `363190881ae6c9f3f39a5a86426254393a6415b66178a871ce11afeee1e4ed07` |
| `tendermint/types/validator.proto` | `d11afbbc8cc831f7d7e5af3a35d7f1641afd1ec0551e1f4d37ef2902d85a0b4c` |
| `tendermint/version/types.proto` | `75f74bdc37f509f28763ddb4f6291e5f397d1df252179d66caf60c9d318066fe` |

## Behavioural rules, and where each one comes from

The schema says what the bytes are. It does not say what a node will accept,
and several of those rules are surprising enough that guessing at them
produces code that looks right. Each one below is cited to a line in the
pinned `cosmos-sdk` v0.55.0 tree, and nothing in `lib/` may encode a rule that
is not here.

| Rule | Source |
| --- | --- |
| Bech32 decoding uses a **1023**-character limit, not BIP-173's 90 | [`types/bech32/bech32.go:21`](https://github.com/cosmos/cosmos-sdk/blob/v0.55.0/types/bech32/bech32.go#L21) — `bech32.Decode(bech, 1023)` |
| Encoding converts 8-bit to 5-bit **with** padding; decoding converts back **without** | [`types/bech32/bech32.go:11`](https://github.com/cosmos/cosmos-sdk/blob/v0.55.0/types/bech32/bech32.go#L11) and [`:26`](https://github.com/cosmos/cosmos-sdk/blob/v0.55.0/types/bech32/bech32.go#L26) |
| Bech32m is never accepted — the SDK calls btcutil's `bech32.Decode`, which implements BIP-173 only | same file |
| An address is any **1 to 255** bytes. It is *not* required to be 20 or 32. | [`types/address.go:166-181`](https://github.com/cosmos/cosmos-sdk/blob/v0.55.0/types/address.go#L166-L181) and [`types/address/store_key.go:10`](https://github.com/cosmos/cosmos-sdk/blob/v0.55.0/types/address/store_key.go#L10) — `MaxAddrLen = 255` |
| 32 bytes is the "base address" length for module and derived addresses | [`types/address/hash.go:17`](https://github.com/cosmos/cosmos-sdk/blob/v0.55.0/types/address/hash.go#L17) — `Len = sha256.Size` |
| Validator and consensus prefixes are the account prefix plus `valoper` and `valcons` | [`types/address.go:66-76`](https://github.com/cosmos/cosmos-sdk/blob/v0.55.0/types/address.go#L66-L76) |
| The default account prefix is `cosmos` | [`types/address.go:39`](https://github.com/cosmos/cosmos-sdk/blob/v0.55.0/types/address.go#L39) |
| A denomination matches `^[a-zA-Z][a-zA-Z0-9/:._-]{2,127}$` — 3 to 128 characters | [`types/coin.go:848`](https://github.com/cosmos/cosmos-sdk/blob/v0.55.0/types/coin.go#L848) |

Two of these are worth stating as prose because they are the ones a reasonable
implementer gets wrong.

**The 90-character cap does not apply.** BIP-173 caps a bech32 string at 90
characters because the BCH code only guarantees detection of up to four
character errors within that length. The Cosmos SDK passes 1023 instead. A
decoder that enforced 90 would reject addresses the chain accepts; this is
why `web3-codec-bech32` takes the cap as a parameter rather than fixing it,
and why every call here passes 1023 explicitly rather than relying on a
default.

**An address is not 20 bytes, and not 32 either.** `VerifyAddressFormat`
checks only that the address is non-empty and no longer than 255 bytes; the
20-byte secp256k1 form and the 32-byte derived form are conventions, not
rules. The SDK's own test suite round-trips a **10-byte** address. So this
library decodes what the chain accepts and lets policy be stricter than the
chain: `Address.of_bytes` takes 1..255, and `Address.is_standard_length` is
what a policy asks when it wants to insist on 20 or 32.

### Cross-implementation vectors

The address vectors in `test/` are the SDK's own literals, lifted from
[`types/address_test.go`](https://github.com/cosmos/cosmos-sdk/blob/v0.55.0/types/address_test.go)
and [`types/bech32/bech32_test.go`](https://github.com/cosmos/cosmos-sdk/blob/v0.55.0/types/bech32/bech32_test.go)
rather than generated here, so that they are evidence about the SDK rather
than about this library agreeing with itself:

| String | Bytes |
| --- | --- |
| `cosmos1qqqsyqcyq5rqwzqfys8f67` | `00010203040506070809` |
| `prefixa1qqqsyqcyq5rqwzqf3953cc` | `00010203040506070809` |
| `prefixb1qqqsyqcyq5rqwzqf20xxpc` | `00010203040506070809` |
| `prefixa1qqqsyqcyq5rqwzqfpg9scrgwpugpzysn7hzdtn` | `000102030405060708090a0b0c0d0e0f10111213` |
| `prefixb1qqqsyqcyq5rqwzqfpg9scrgwpugpzysnrujsuw` | `000102030405060708090a0b0c0d0e0f10111213` |

The last two are the same twenty bytes under two prefixes, which is the
property this library exists to keep visible.

## Refreshing

```sh
# 1. move a pin in tools/fetch-proto.sh, then
tools/fetch-proto.sh

# 2. regenerate. Needs the web3-protoc switch and a protoc; see docs/switch.md.
PATH="$HOME/.opam/web3-protoc/bin:$PATH" tools/gen-proto.sh

# 3. regenerate this table
#    (the script that produced it lives in the commit that added this file)

# 4. and check what actually moved before believing it was harmless
git diff --stat proto/ lib/proto/gen/
```

`tools/gen-proto.sh` delegates to `../ocaml-web3-codec/tools/gen-protobuf.sh`,
the shared invocation every chain library in this tree uses. The one flag this
repository adds is `prefix_output_with_package=true`: Cosmos defines four
`tx.proto`, three `keys.proto` and two `query.proto` in different packages, and
without the prefix the plugin reports "Tried to write the same file twice" and
emits nothing at all. That flag was added to the shared script for this
repository and defaults to off, so no other consumer changes.

## What the generated bindings are not

They are wire types, not a validated model. Every message in a `TxBody` is a
`google.protobuf.Any` that the generated code cannot narrow, and narrowing it —
deciding which `type_url` values this library is willing to explain to a
human — is `cosmos-tx`'s job, not `cosmos-proto`'s.
