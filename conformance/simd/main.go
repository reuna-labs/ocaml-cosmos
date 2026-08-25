// The Go SDK oracle.
//
// Builds the same transaction ocaml-cosmos's tests build, using cosmos-sdk
// v0.55.0 itself, and prints what it serialises to. Two questions are being
// answered, and only the SDK can answer the second:
//
//   - the protobuf encoding of SignDoc, which protoc also settles;
//   - the SIGN_MODE_LEGACY_AMINO_JSON encoding, which nothing else does.
//
// Amino JSON is where an implementation written from a reading of the schema
// goes quietly wrong. The options governing it -- dont_omitempty,
// legacy_coins, inline_json -- interact with key ordering and with how numbers
// are spelled, and the only authority is the encoder in this module.
//
// Nothing here touches a network. The account number, sequence, fee, timeout
// and keys are constants, matching conformance/protoc/*.txtpb, so a mismatch
// is a disagreement about encoding rather than about who called a node.
//
// usage: conformance/simd/generate.sh
package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"os"

	apitx "cosmossdk.io/api/cosmos/tx/v1beta1"
	signingapi "cosmossdk.io/api/cosmos/tx/signing/v1beta1"
	// The SDK vendored x/tx into itself at v0.55. Importing cosmossdk.io/x/tx
	// as well registers the same proto file twice and panics at init.
	txsigning "github.com/cosmos/cosmos-sdk/x/tx/signing"
	"github.com/cosmos/cosmos-sdk/x/tx/signing/aminojson"
	"google.golang.org/protobuf/proto"

	codectypes "github.com/cosmos/cosmos-sdk/codec/types"
	cryptotypes "github.com/cosmos/cosmos-sdk/crypto/types"
	"github.com/cosmos/cosmos-sdk/crypto/keys/secp256k1"
	"cosmossdk.io/math"
	sdk "github.com/cosmos/cosmos-sdk/types"
	txtypes "github.com/cosmos/cosmos-sdk/types/tx"
	"github.com/cosmos/cosmos-sdk/types/tx/signing"
	banktypes "github.com/cosmos/cosmos-sdk/x/bank/types"
	transfertypes "github.com/cosmos/ibc-go/v11/modules/apps/transfer/types"
	clienttypes "github.com/cosmos/ibc-go/v11/modules/core/02-client/types"
	wasmtypes "github.com/CosmWasm/wasmd/x/wasm/types"
)

// The three addresses in conformance/protoc/*.txtpb, derived from private
// keys 1, 2 and 3 in conformance/oracle/secp256k1.py.
const (
	addr1 = "cosmos1w508d6qejxtdg4y5r3zarvary0c5xw7k6ah60c"
	addr2 = "cosmos1q6hag67dl53wl99vzg42z8eyzfz2xlkvsrxukv"
	addr3 = "cosmos10ht9tyks4vh7p5p904t340cr9nvahy7u8e84x9"

	chainID       = "cosmoshub-4"
	accountNumber = 42
	sequence      = 7
	gasLimit      = 200000
	memo          = "sent by ocaml-cosmos"
	timeoutHeight = 20000000
)

func must[T any](v T, err error) T {
	if err != nil {
		panic(err)
	}
	return v
}

func amount(s string) math.Int {
	v, ok := math.NewIntFromString(s)
	if !ok {
		panic("not an integer: " + s)
	}
	return v
}

func coins(denom, a string) sdk.Coins {
	return sdk.NewCoins(sdk.NewCoin(denom, amount(a)))
}

func msgSend() sdk.Msg {
	return &banktypes.MsgSend{
		FromAddress: addr1,
		ToAddress:   addr2,
		Amount:      coins("uatom", "1000000"),
	}
}

func msgMultiSend() sdk.Msg {
	return &banktypes.MsgMultiSend{
		Inputs:  []banktypes.Input{{Address: addr1, Coins: coins("uatom", "3000000")}},
		Outputs: []banktypes.Output{
			{Address: addr2, Coins: coins("uatom", "1000000")},
			{Address: addr3, Coins: coins("uatom", "2000000")},
		},
	}
}

func msgTransfer() sdk.Msg {
	return &transfertypes.MsgTransfer{
		SourcePort:    "transfer",
		SourceChannel: "channel-141",
		Token:         sdk.NewCoin("uatom", amount("500000")),
		Sender:        addr1,
		Receiver:      "osmo1w508d6qejxtdg4y5r3zarvary0c5xw7kdjmmmt",
		TimeoutHeight: clienttypes.Height{RevisionNumber: 1, RevisionHeight: 20000000},
		TimeoutTimestamp: 1774000000000000000,
	}
}

func msgExecute() sdk.Msg {
	return &wasmtypes.MsgExecuteContract{
		Sender:   addr1,
		Contract: addr2,
		Msg:      wasmtypes.RawContractMessage(`{"transfer":{"recipient":"cosmos10ht9tyks4vh7p5p904t340cr9nvahy7u8e84x9","amount":"250"}}`),
		Funds:    coins("uatom", "1"),
	}
}

// aminoJSON is what SIGN_MODE_LEGACY_AMINO_JSON actually signs.
//
// Not legacytx.StdSignBytes: that is deprecated upstream, and it drives the
// encoding from Go struct tags. The handler below is x/tx/signing/aminojson,
// which drives it from the amino.* options in the .proto files -- dont_omitempty,
// legacy_coins, inline_json -- and is what a v0.50-and-later node verifies
// against. The two can disagree, so the choice matters.
//
// The handler wants the pulsar types rather than the gogo ones, so the bytes
// produced above are unmarshalled back into them. That is not a detour: it is
// a check that the two representations agree on the same bytes.
func aminoJSON(bodyBytes, authInfoBytes []byte) string {
	body := &apitx.TxBody{}
	if err := proto.Unmarshal(bodyBytes, body); err != nil {
		panic(err)
	}
	authInfo := &apitx.AuthInfo{}
	if err := proto.Unmarshal(authInfoBytes, authInfo); err != nil {
		panic(err)
	}
	handler := aminojson.NewSignModeHandler(aminojson.SignModeHandlerOptions{})
	if handler.Mode() != signingapi.SignMode_SIGN_MODE_LEGACY_AMINO_JSON {
		panic("wrong sign mode")
	}
	out, err := handler.GetSignBytes(
		context.Background(),
		txsigning.SignerData{
			Address:       addr1,
			ChainID:       chainID,
			AccountNumber: accountNumber,
			Sequence:      sequence,
			PubKey:        nil,
		},
		txsigning.TxData{
			Body:          body,
			AuthInfo:      authInfo,
			BodyBytes:     bodyBytes,
			AuthInfoBytes: authInfoBytes,
		},
	)
	if err != nil {
		panic(err)
	}
	return string(out)
}

func protoAny(msg sdk.Msg) *codectypes.Any {
	return must(codectypes.NewAnyWithValue(msg))
}

// envelope builds the TxBody and AuthInfo for a message set, using the same
// constants throughout, and returns their encodings.
func envelope(msgs []sdk.Msg) (bodyBytes, authInfoBytes []byte) {
	anys := make([]*codectypes.Any, 0, len(msgs))
	for _, m := range msgs {
		anys = append(anys, protoAny(m))
	}
	body := &txtypes.TxBody{
		Messages:      anys,
		Memo:          memo,
		TimeoutHeight: timeoutHeight,
	}
	pubkeyBytes := must(hex.DecodeString(
		"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"))
	var pk cryptotypes.PubKey = &secp256k1.PubKey{Key: pubkeyBytes}
	authInfo := &txtypes.AuthInfo{
		SignerInfos: []*txtypes.SignerInfo{{
			PublicKey: protoAny(pk),
			ModeInfo: &txtypes.ModeInfo{Sum: &txtypes.ModeInfo_Single_{
				Single: &txtypes.ModeInfo_Single{Mode: signing.SignMode_SIGN_MODE_DIRECT},
			}},
			Sequence: sequence,
		}},
		Fee: &txtypes.Fee{
			Amount:   coins("uatom", "1000"),
			GasLimit: gasLimit,
		},
	}
	return must(body.Marshal()), must(authInfo.Marshal())
}

func aminoFor(msgs []sdk.Msg) string {
	b, a := envelope(msgs)
	return aminoJSON(b, a)
}

func main() {
	pubkeyBytes := must(hex.DecodeString(
		"0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"))
	var pk cryptotypes.PubKey = &secp256k1.PubKey{Key: pubkeyBytes}

	body := &txtypes.TxBody{
		Messages:      []*codectypes.Any{protoAny(msgSend())},
		Memo:          memo,
		TimeoutHeight: timeoutHeight,
	}
	authInfo := &txtypes.AuthInfo{
		SignerInfos: []*txtypes.SignerInfo{{
			PublicKey: protoAny(pk),
			ModeInfo: &txtypes.ModeInfo{Sum: &txtypes.ModeInfo_Single_{
				Single: &txtypes.ModeInfo_Single{Mode: signing.SignMode_SIGN_MODE_DIRECT},
			}},
			Sequence: sequence,
		}},
		Fee: &txtypes.Fee{
			Amount:   coins("uatom", "1000"),
			GasLimit: gasLimit,
		},
	}
	bodyBytes := must(body.Marshal())
	authInfoBytes := must(authInfo.Marshal())
	signDoc := &txtypes.SignDoc{
		BodyBytes:     bodyBytes,
		AuthInfoBytes: authInfoBytes,
		ChainId:       chainID,
		AccountNumber: accountNumber,
	}

	out := map[string]any{
		"_note": "Generated by conformance/simd. Do not edit.",
		"proto": map[string]string{
			"msg_send":       hex.EncodeToString(must(msgSend().(*banktypes.MsgSend).Marshal())),
			"msg_multi_send": hex.EncodeToString(must(msgMultiSend().(*banktypes.MsgMultiSend).Marshal())),
			"msg_transfer":   hex.EncodeToString(must(msgTransfer().(*transfertypes.MsgTransfer).Marshal())),
			"msg_execute":    hex.EncodeToString(must(msgExecute().(*wasmtypes.MsgExecuteContract).Marshal())),
			"tx_body":        hex.EncodeToString(bodyBytes),
			"auth_info":      hex.EncodeToString(authInfoBytes),
			"sign_doc":       hex.EncodeToString(must(signDoc.Marshal())),
		},
		"amino": map[string]string{
			"send":       aminoFor([]sdk.Msg{msgSend()}),
			"multi_send": aminoFor([]sdk.Msg{msgMultiSend()}),
			"transfer":   aminoFor([]sdk.Msg{msgTransfer()}),
			"execute":    aminoFor([]sdk.Msg{msgExecute()}),
			"two_msgs":   aminoFor([]sdk.Msg{msgSend(), msgSend()}),
		},
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(out); err != nil {
		panic(err)
	}
}
