#!/bin/bash
#
# Vendor the pinned .proto tree into proto/.
#
# Cosmos has no single schema repository. The transaction envelope lives in
# cosmos-sdk, IBC in ibc-go, CosmWasm in wasmd, and all three import extension
# definitions from three more repositories. Every one of those is pinned to an
# exact tag below, and the imports are resolved recursively so that the tree in
# proto/ is closed: `protoc -I ./proto` needs nothing else on the machine.
#
# The output is COMMITTED, and so are the bindings generated from it, so an
# ordinary build needs neither this script nor a network. Run it only when a
# pin moves, then re-run tools/gen-proto.sh and update docs/protocol-pin.md.
#
# usage: tools/fetch-proto.sh

set -eu

cd "$(dirname "$0")/.."

# --- the pins. Change here, nowhere else. -----------------------------------
SDK_TAG=v0.55.0            # cosmos/cosmos-sdk        64fd208a11fb54f7ffdca1a1290c2cfbbc254e49
IBC_TAG=v11.2.0            # cosmos/ibc-go            cfc072e53eee42b2ab804cd4344ba610016f793c
WASMD_TAG=v0.70.3          # CosmWasm/wasmd
COSMOS_PROTO_REF=3e53812559a5f89540930b1a40f16266a73ce1c9   # cosmos/cosmos-proto
GOGOPROTO_REF=fc9edf209aa440a4be74ffe4ec389759c664472c      # cosmos/gogoproto
COMETBFT_TAG=v0.38.17      # cometbft/cometbft -- the tendermint/* namespace
GOOGLEAPIS_REF=2e9c5681901a2eebf7f547f0b60c895b1732415e   # googleapis/googleapis -- google/api/*. Pinned rather than
                     # tracking master: an unpinned fetch is not reproducible,
                     # even for files that are only stubbed.
PROTOBUF_TAG=v32.0         # protocolbuffers/protobuf -- google/protobuf/*

# --- the entry points. Transitive imports are discovered, not listed. --------
ROOTS="
cosmos/tx/v1beta1/tx.proto
cosmos/tx/v1beta1/service.proto
cosmos/tx/signing/v1beta1/signing.proto
cosmos/base/v1beta1/coin.proto
cosmos/base/abci/v1beta1/abci.proto
cosmos/crypto/secp256k1/keys.proto
cosmos/crypto/ed25519/keys.proto
cosmos/crypto/multisig/keys.proto
cosmos/crypto/multisig/v1beta1/multisig.proto
cosmos/auth/v1beta1/auth.proto
cosmos/auth/v1beta1/query.proto
cosmos/bank/v1beta1/tx.proto
cosmos/bank/v1beta1/query.proto
ibc/applications/transfer/v1/tx.proto
cosmwasm/wasm/v1/tx.proto
google/protobuf/any.proto
google/protobuf/timestamp.proto
google/protobuf/duration.proto
google/protobuf/descriptor.proto
"

# Maps an import path to the raw URL that serves it.
url_for() {
  case "$1" in
    cosmos/*|amino/*)
      echo "https://raw.githubusercontent.com/cosmos/cosmos-sdk/$SDK_TAG/proto/$1" ;;
    ibc/*|capability/*)
      echo "https://raw.githubusercontent.com/cosmos/ibc-go/$IBC_TAG/proto/$1" ;;
    cosmwasm/*)
      echo "https://raw.githubusercontent.com/CosmWasm/wasmd/$WASMD_TAG/proto/$1" ;;
    cosmos_proto/*)
      echo "https://raw.githubusercontent.com/cosmos/cosmos-proto/$COSMOS_PROTO_REF/proto/$1" ;;
    gogoproto/*)
      echo "https://raw.githubusercontent.com/cosmos/gogoproto/$GOGOPROTO_REF/$1" ;;
    tendermint/*)
      echo "https://raw.githubusercontent.com/cometbft/cometbft/$COMETBFT_TAG/proto/$1" ;;
    cometbft/*)
      echo "https://raw.githubusercontent.com/cometbft/cometbft/main/proto/$1" ;;
    google/api/*)
      echo "https://raw.githubusercontent.com/googleapis/googleapis/$GOOGLEAPIS_REF/$1" ;;
    google/protobuf/*)
      # Vendored rather than taken from protoc's builtin include path, so that
      # the generated output does not depend on which protoc is installed.
      echo "https://raw.githubusercontent.com/protocolbuffers/protobuf/$PROTOBUF_TAG/src/$1" ;;
    *)
      echo "" ;;
  esac
}

rm -rf proto
mkdir -p proto

pending="$ROOTS"
done_list=""

while [ -n "$(echo "$pending" | tr -d '[:space:]')" ]; do
  next=""
  for f in $pending; do
    case " $done_list " in *" $f "*) continue ;; esac
    done_list="$done_list $f"

    url="$(url_for "$f")"
    if [ -z "$url" ]; then
      echo "no source configured for import: $f" >&2
      exit 1
    fi

    mkdir -p "proto/$(dirname "$f")"
    if ! curl -sSf "$url" -o "proto/$f"; then
      echo "fetch failed: $f  <- $url" >&2
      exit 1
    fi
    echo "  $f"

    # Its imports become the next round.
    # BSD sed has no \?, so this matches "import [public] \"path\";" without one.
    imports=$(sed -n 's/^[[:space:]]*import[[:space:]][^"]*"\([^"]*\)".*/\1/p' "proto/$f")
    next="$next $imports"
  done
  pending="$next"
done

echo
echo "vendored $(find proto -name '*.proto' | wc -l | tr -d ' ') files"
