#!/bin/bash
#
# CosmJS as a differential oracle.
#
# The third implementation of the same transaction, and the one that speaks for
# the ecosystem rather than for the specification: this is what wallets and
# front ends run, so a library that matched the SDK and disagreed with CosmJS
# would be correct and unusable.
#
# usage: conformance/cosmjs/generate.sh
#        git diff --exit-code conformance/fixtures/
#
# Requires Node and, on the first run, network access to fetch the packages.

set -euo pipefail
cd "$(dirname "$0")"

command -v node >/dev/null || { echo "node is not on PATH" >&2; exit 1; }

[ -d node_modules ] || npm ci --silent
mkdir -p ../fixtures
node generate.mjs > ../fixtures/cosmjs.json
echo "  wrote conformance/fixtures/cosmjs.json"

# The three oracles must agree; see check.py for why this is a cross-check
# rather than another set of committed bytes.
exec python3 check.py
