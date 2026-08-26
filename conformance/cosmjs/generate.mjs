// CosmJS as a differential oracle.
//
// The third implementation of the same transaction, after protoc (the wire
// format) and the Go SDK (the protocol). This one matters for a different
// reason: it is what the ecosystem's wallets and front ends actually run, so a
// disagreement here is a disagreement with what users' keys will sign, whatever
// the specification says.
//
// It builds the transaction conformance/protoc/*.txtpb describes, from the same
// constants, and prints what it serialises to -- both the protobuf encodings and
// the SIGN_MODE_LEGACY_AMINO_JSON document.
//
// Nothing here touches a network. No node is asked for an account number or a
// sequence; they are constants, so a mismatch is a disagreement about encoding
// rather than about who called what.
//
// usage: npm ci && npm run generate

import { TxBody, AuthInfo, SignDoc, Fee, SignerInfo, ModeInfo } from "cosmjs-types/cosmos/tx/v1beta1/tx.js";
import { SignMode } from "cosmjs-types/cosmos/tx/signing/v1beta1/signing.js";
import { MsgSend, MsgMultiSend } from "cosmjs-types/cosmos/bank/v1beta1/tx.js";
import { MsgTransfer } from "cosmjs-types/ibc/applications/transfer/v1/tx.js";
import { MsgExecuteContract } from "cosmjs-types/cosmwasm/wasm/v1/tx.js";
import { PubKey } from "cosmjs-types/cosmos/crypto/secp256k1/keys.js";
import { Any } from "cosmjs-types/google/protobuf/any.js";
import { makeSignDoc as makeAminoSignDoc, serializeSignDoc } from "@cosmjs/amino";

// The same addresses and constants as conformance/protoc and conformance/simd.
const addr1 = "cosmos1w508d6qejxtdg4y5r3zarvary0c5xw7k6ah60c";
const addr2 = "cosmos1q6hag67dl53wl99vzg42z8eyzfz2xlkvsrxukv";
const addr3 = "cosmos10ht9tyks4vh7p5p904t340cr9nvahy7u8e84x9";

const chainId = "cosmoshub-4";
const accountNumber = 42;
const sequence = 7;
const gasLimit = 200000;
const memo = "sent by ocaml-cosmos";
const timeoutHeight = 20000000;

const pubkeyHex = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798";
const pubkeyBytes = Uint8Array.from(Buffer.from(pubkeyHex, "hex"));

const hex = (u8) => Buffer.from(u8).toString("hex");

const msgSend = () =>
  MsgSend.fromPartial({
    fromAddress: addr1,
    toAddress: addr2,
    amount: [{ denom: "uatom", amount: "1000000" }],
  });

const msgMultiSend = () =>
  MsgMultiSend.fromPartial({
    inputs: [{ address: addr1, coins: [{ denom: "uatom", amount: "3000000" }] }],
    outputs: [
      { address: addr2, coins: [{ denom: "uatom", amount: "1000000" }] },
      { address: addr3, coins: [{ denom: "uatom", amount: "2000000" }] },
    ],
  });

const msgTransfer = () =>
  MsgTransfer.fromPartial({
    sourcePort: "transfer",
    sourceChannel: "channel-141",
    token: { denom: "uatom", amount: "500000" },
    sender: addr1,
    receiver: "osmo1w508d6qejxtdg4y5r3zarvary0c5xw7kdjmmmt",
    timeoutHeight: { revisionNumber: 1n, revisionHeight: 20000000n },
    timeoutTimestamp: 1774000000000000000n,
  });

const msgExecute = () =>
  MsgExecuteContract.fromPartial({
    sender: addr1,
    contract: addr2,
    msg: Uint8Array.from(
      Buffer.from(
        `{"transfer":{"recipient":"cosmos10ht9tyks4vh7p5p904t340cr9nvahy7u8e84x9","amount":"250"}}`
      )
    ),
    funds: [{ denom: "uatom", amount: "1" }],
  });

const anyOf = (typeUrl, bytes) => Any.fromPartial({ typeUrl, value: bytes });

const bodyBytes = () =>
  TxBody.encode(
    TxBody.fromPartial({
      messages: [anyOf("/cosmos.bank.v1beta1.MsgSend", MsgSend.encode(msgSend()).finish())],
      memo,
      timeoutHeight: BigInt(timeoutHeight),
    })
  ).finish();

const authInfoBytes = () =>
  AuthInfo.encode(
    AuthInfo.fromPartial({
      signerInfos: [
        SignerInfo.fromPartial({
          publicKey: anyOf(
            "/cosmos.crypto.secp256k1.PubKey",
            PubKey.encode(PubKey.fromPartial({ key: pubkeyBytes })).finish()
          ),
          modeInfo: ModeInfo.fromPartial({ single: { mode: SignMode.SIGN_MODE_DIRECT } }),
          sequence: BigInt(sequence),
        }),
      ],
      fee: Fee.fromPartial({
        amount: [{ denom: "uatom", amount: "1000" }],
        gasLimit: BigInt(gasLimit),
      }),
    })
  ).finish();

const signDocBytes = () => {
  const body = bodyBytes();
  const auth = authInfoBytes();
  return SignDoc.encode(
    SignDoc.fromPartial({
      bodyBytes: body,
      authInfoBytes: auth,
      chainId,
      accountNumber: BigInt(accountNumber),
    })
  ).finish();
};

// SIGN_MODE_LEGACY_AMINO_JSON. @cosmjs/amino builds the StdSignDoc and
// serializeSignDoc produces the exact bytes a signature covers -- sorted keys,
// no whitespace. The amino type names are CosmJS's own, which is the point:
// if they disagreed with the SDK's (amino.name) options, that would be the
// finding.
const aminoDoc = (msgs) =>
  Buffer.from(
    serializeSignDoc(
      makeAminoSignDoc(
        msgs,
        { amount: [{ denom: "uatom", amount: "1000" }], gas: String(gasLimit) },
        chainId,
        memo,
        accountNumber,
        sequence,
        timeoutHeight
      )
    )
  ).toString();

const aminoSend = [
  {
    type: "cosmos-sdk/MsgSend",
    value: {
      from_address: addr1,
      to_address: addr2,
      amount: [{ denom: "uatom", amount: "1000000" }],
    },
  },
];

const out = {
  _note: "Generated by conformance/cosmjs. Do not edit.",
  _versions: {
    "@cosmjs/proto-signing": JSON.parse(
      await import("node:fs").then((fs) =>
        fs.readFileSync("./node_modules/@cosmjs/proto-signing/package.json", "utf8")
      )
    ).version,
  },
  proto: {
    msg_send: hex(MsgSend.encode(msgSend()).finish()),
    msg_multi_send: hex(MsgMultiSend.encode(msgMultiSend()).finish()),
    msg_transfer: hex(MsgTransfer.encode(msgTransfer()).finish()),
    msg_execute: hex(MsgExecuteContract.encode(msgExecute()).finish()),
    pubkey: hex(PubKey.encode(PubKey.fromPartial({ key: pubkeyBytes })).finish()),
    tx_body: hex(bodyBytes()),
    auth_info: hex(authInfoBytes()),
    sign_doc: hex(signDocBytes()),
  },
  amino: {
    send: aminoDoc(aminoSend),
  },
};

console.log(JSON.stringify(out, null, 2));
