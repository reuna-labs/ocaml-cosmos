# Security

## Status

**Public, unaudited alpha. Do not use this to control assets of value.**

`v0.1.0-alpha2`, its dependency closure and guarded testnet evidence are public.
The hermetic suite, no-I/O boundary, conformance oracles and six bounded
Crowbar targets pass, but there has been no sustained fuzz campaign or
independent review. The launch gates therefore place release and assurance at
partial, not complete.

## Reporting

Privately, to `security@reuna.io`. Please do not open a public issue for
anything affecting the signing path.

## Worth knowing before you read any of this code

**A protobuf decoder in this stack has already had a memory-safety bug.**
Fuzzing `ocaml-tron` found a segfault in `ocaml-protoc-plugin`'s reader
reachable from 85 bytes: an integer overflow in a bounds check let
`String.unsafe_blit` read past the buffer. It is fixed in the vendored runtime
in `ocaml-web3-codec`, which this repository depends on.

Two things about it matter here. No caller-side guard could have helped — a
segfault is not an exception, so neither `Result.catch` nor a `try` around
`from_proto` would have caught it. And this repository decodes far more
protobuf from a node than `ocaml-tron` does, because the Cosmos query surface
is protobuf all the way down.

## The threat model in one line

The node is the adversary — not a hypothetical compromised one, the ordinary
one, because a signer that is only correct against an honest node is not a
signer. `docs/threat-model.md` has the rest.

## The three mistakes this code is shaped to prevent

1. **Signing a re-encode.** `SignDoc` covers `body_bytes` and
   `auth_info_bytes` as opaque strings. They are retained and reframed, never
   re-serialized from a decoded model, because protobuf admits encodings that
   decode alike and re-encode differently.
2. **Approving what cannot be explained.** Every message is a
   `google.protobuf.Any`; anything outside the allow-list is opaque and no
   policy can accept it.
3. **Calling a broadcast a confirmation.** A code-0 `broadcast_tx_sync` means
   the transaction reached a mempool. It has not executed.
