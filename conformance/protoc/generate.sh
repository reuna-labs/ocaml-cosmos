#!/bin/bash
#
# Golden protobuf encodings, produced by protoc itself.
#
# protoc is the reference implementation of the format, written in C++ and
# sharing nothing with ocaml-protoc-plugin. Comparing against it establishes
# that this library's bytes are what the format says, which no amount of
# round-tripping through our own encoder could.
#
# Input is text format, which is unambiguous and reviewable in a way a hex
# string is not: the .txtpb files say what the transaction is, and the .hex
# files say what it serialises to.
#
# usage: conformance/protoc/generate.sh
#        git diff --exit-code conformance/fixtures/protoc
#
# Requires protoc on PATH. Nothing else -- no network, no SDK, no toolchain.

set -eu
cd "$(dirname "$0")/../.."

out=conformance/fixtures/protoc
mkdir -p "$out"

emit() {
  name="$1"; message="$2"; file="$3"
  protoc -I proto "--encode=$message" "$file" \
    < "conformance/protoc/$name.txtpb" \
    | xxd -p | tr -d '\n' > "$out/$name.hex"
  printf '\n' >> "$out/$name.hex"
  echo "  $name  <- $message"
}

# Fills @@name@@ placeholders in a .txtpb.in from the .hex files already
# produced. See expand.py for why protoc's own Any expansion is not used.
expand() {
  python3 conformance/protoc/expand.py "$1" "$out"
}

emit msg_send       cosmos.bank.v1beta1.MsgSend      cosmos/bank/v1beta1/tx.proto
emit msg_multi_send cosmos.bank.v1beta1.MsgMultiSend cosmos/bank/v1beta1/tx.proto
emit msg_transfer   ibc.applications.transfer.v1.MsgTransfer \
                                                     ibc/applications/transfer/v1/tx.proto
emit msg_execute    cosmwasm.wasm.v1.MsgExecuteContract cosmwasm/wasm/v1/tx.proto

expand pubkey
emit pubkey         cosmos.crypto.secp256k1.PubKey   cosmos/crypto/secp256k1/keys.proto
expand auth_info
emit auth_info      cosmos.tx.v1beta1.AuthInfo       cosmos/tx/v1beta1/tx.proto

# These two embed the encodings above, so they are generated after them.
expand tx_body
emit tx_body        cosmos.tx.v1beta1.TxBody         cosmos/tx/v1beta1/tx.proto
expand sign_doc
emit sign_doc       cosmos.tx.v1beta1.SignDoc        cosmos/tx/v1beta1/tx.proto
