#!/bin/bash
#
# Record real CometBFT JSON-RPC responses as decoder fixtures.
#
# The point is that these are what a node actually sends, not what a reading of
# CometBFT's Go structs suggests it sends. The two differ in ways that matter
# to a decoder and that are invisible in the type definitions:
#
#   - int64 and uint64 fields are JSON *strings*, uint32 fields are JSON
#     numbers, so "height":"32675051" sits beside "code":0;
#   - absent fields are null rather than omitted;
#   - the key is "proofOps", camelCase, where the Go field is ProofOps and the
#     surrounding names are snake_case.
#
# Read-only. Every call here is a query; nothing is broadcast. The addresses
# are public, and one of them is the BIP-173 example key, which someone has
# used on mainnet.
#
# usage: conformance/rpc/record.sh [endpoint]
#        git diff --exit-code conformance/fixtures/rpc
#
# Re-recording moves the block heights, so a diff after running this is
# expected and is not a failure. The fixtures are pinned so that the *decoder*
# is tested against a fixed input, not so that the chain is.

set -eu
cd "$(dirname "$0")/../.."

EP="${1:-https://cosmos-rpc.publicnode.com}"
out=conformance/fixtures/rpc
mkdir -p "$out"

get() {
  name="$1"; shift
  curl -sS --max-time 30 "$@" > "$out/$name.json"
  printf '\n' >> "$out/$name.json"
  echo "  $name ($(wc -c < "$out/$name.json" | tr -d ' ') bytes)"
}

# An auth Query/Account request is one length-delimited string field.
account_query() {
  python3 -c "
import sys
a = sys.argv[1].encode()
print((b'\x0a' + bytes([len(a)]) + a).hex())
" "$1"
}

get status "$EP/status"

# A BaseAccount: what a signer needs before it can build anything, because the
# account number and sequence are both in here.
get account_base -G "$EP/abci_query" \
  --data-urlencode 'path="/cosmos.auth.v1beta1.Query/Account"' \
  --data-urlencode "data=0x$(account_query cosmos1w508d6qejxtdg4y5r3zarvary0c5xw7k6ah60c)"

# A ModuleAccount: the same query returning a different type inside the Any,
# which a decoder that assumed BaseAccount would read as nonsense.
get account_module -G "$EP/abci_query" \
  --data-urlencode 'path="/cosmos.auth.v1beta1.Query/Account"' \
  --data-urlencode "data=0x$(account_query cosmos1fl48vsnmsdzcv85q5d2q4z5ajdha8yu34mf0eh)"

# A well-formed address nobody has used. The ABCI code is non-zero and the
# failure is in the *response*, not in the JSON-RPC envelope -- a distinction
# the decoder has to keep, because one means "the node answered and the answer
# is no" and the other means "the node did not answer".
get account_missing -G "$EP/abci_query" \
  --data-urlencode 'path="/cosmos.auth.v1beta1.Query/Account"' \
  --data-urlencode "data=0x$(account_query cosmos142424242424242424242424242424242a7m5mu)"

# A malformed address. Same shape as above with a different ABCI code, and
# worth keeping separate: "you asked wrong" and "there is nothing there" are
# not the same answer.
get account_bad_address -G "$EP/abci_query" \
  --data-urlencode 'path="/cosmos.auth.v1beta1.Query/Account"' \
  --data-urlencode "data=0x$(account_query cosmos1qqqsyqcyq5rqwzqfys8f67kzy4mkm5qxu5xvj5)"

# A JSON-RPC level error: the envelope carries "error" and no "result" at all.
# It has to be a POST of a real JSON-RPC request -- a bad URL path gets an
# HTTP 404 with a plain-text body, which is a different failure.
get error_unknown_method -X POST -H 'Content-Type: application/json' \
  --data '{"jsonrpc":"2.0","id":1,"method":"no_such_method","params":{}}' "$EP"

echo
echo "Recorded against $EP"
