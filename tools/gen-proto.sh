#!/bin/bash
#
# Regenerate the OCaml protobuf bindings under lib/proto/gen/ from proto/.
#
# The output is COMMITTED, so building ocaml-cosmos needs neither protoc nor
# the plugin. Run this only after tools/fetch-proto.sh has moved a pin, then
# update docs/protocol-pin.md.
#
# The invocation itself is not ours: ../ocaml-web3-codec/tools/gen-protobuf.sh
# is the shared one, and it carries the flags (int64_as_int=false, no
# [@@deriving show]) and the lazify-merge pass that every chain library in this
# tree needs. Only the file list below belongs to this repository.
#
# requires: the web3-protoc switch (see docs/switch.md) and a protoc on PATH.
#
# usage: tools/gen-proto.sh

set -eu

cd "$(dirname "$0")/.."

CODEC="${CODEC:-../ocaml-web3-codec}"
[ -x "$CODEC/tools/gen-protobuf.sh" ] || {
  echo "shared generator not found at $CODEC/tools/gen-protobuf.sh" >&2
  echo "set CODEC to the ocaml-web3-codec checkout" >&2
  exit 1; }

# Everything under proto/ except two groups.
#
#   google/protobuf/  the well-known types, generated separately into
#                     gen/google_types/ (see the shared script for why).
#                     descriptor.proto is in that list because the extension
#                     definitions -- gogoproto, amino, cosmos_proto,
#                     cosmos.msg.v1, cosmos.query.v1 -- all extend its option
#                     messages, and without it their accessors do not compile.
#
#   google/api/       grpc-gateway HTTP mappings. They are service options and
#                     never appear on the wire; this library does not implement
#                     the REST gateway. They are stubbed by hand in
#                     lib/proto/stubs/ instead of generated, because
#                     http.proto's doc comment contains "{get|put|post|...}",
#                     which OCaml reads as an unterminated string literal
#                     inside a comment and refuses to compile.
files=$(cd proto && find . -name '*.proto' | sed 's|^\./||' \
          | grep -v '^google/protobuf/' | grep -v '^google/api/' | sort)

# -p prefix_output_with_package=true is not optional here. Cosmos defines four
# tx.proto, three keys.proto and two query.proto in different packages, and the
# plugin names output files after the basename; without the prefix it reports
# "Tried to write the same file twice" and emits nothing at all.
exec "$CODEC/tools/gen-protobuf.sh" -I ./proto -o ./lib/proto/gen \
  -p prefix_output_with_package=true \
  $files \
  -- google/protobuf/any.proto \
     google/protobuf/timestamp.proto \
     google/protobuf/duration.proto \
     google/protobuf/descriptor.proto
