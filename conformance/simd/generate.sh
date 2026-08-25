#!/bin/bash
#
# The Go SDK oracle.
#
# Runs cosmos-sdk v0.55.0's own encoders over the same transaction the protoc
# fixtures describe, and writes both what it serialises to and -- the part
# nothing else can supply -- what SIGN_MODE_LEGACY_AMINO_JSON signs.
#
# The protobuf half overlaps with conformance/protoc deliberately. Two
# independent oracles agreeing on the same bytes is worth more than either
# alone, and a disagreement between them would be the finding.
#
# usage: conformance/simd/generate.sh
#        git diff --exit-code conformance/fixtures/
#
# Requires Go and, on the first run, network access to fetch the SDK.

set -eu
cd "$(dirname "$0")"

mkdir -p ../fixtures
# sonic prints a warning about the host CPU to stderr; it is not a failure.
GOFLAGS=-mod=mod go run . 2>/dev/null > ../fixtures/sdk.json
echo "  wrote conformance/fixtures/sdk.json"

# Split the amino half into raw files, and check the protobuf half against
# protoc. See split.py.
exec python3 split.py
