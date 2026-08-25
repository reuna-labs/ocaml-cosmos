# Threat model

Status: **draft**. This is the shape of the argument, written at scaffold time
so that L1–L4 are built against it rather than having it reverse-engineered at
review time. It is not an assurance artefact and no independent review has
happened.

## What this library is for

Constructing, explaining and signing Cosmos SDK transactions inside a
confidential enclave, and submitting them to a node the enclave does not
control and does not trust.

## The adversary

The node. Not a hypothetical compromised node — the ordinary one, because a
signer that is only correct against an honest node is not a signer. It can:

- return any bytes, of any size, in any encoding, at any time or never;
- return a stale, forked or fabricated view of chain state;
- report a transaction as accepted when it was dropped, or dropped when it was
  accepted;
- replay, delay or reorder anything the enclave sent it.

Secondarily: whoever submits an intent to be signed, who may be trying to get a
transaction approved that does not mean what the approval says it means.

## What is defended

| Property | How |
| --- | --- |
| The bytes displayed are the bytes signed | Intent is derived from the serialized `body_bytes`/`auth_info_bytes`, never from the builder's inputs |
| The bytes signed are the bytes broadcast | `SignDoc` retains its source bytes; `TxRaw` frames them rather than re-encoding a decoded model |
| An unexplainable transaction is not approved | Every message is an `Any`; a `type_url` outside the allow-list is opaque and no policy can accept it |
| The signature cannot be reshaped in flight | Low-S normalisation, which the SDK also enforces on the verifying side |
| A signer cannot be walked into widening its own validity window | Nothing reads a clock; `timeout_height` and `timeout_timestamp` are inputs |
| Replay is bounded | `chain_id` and `account_number` are inside `SignDoc`; `sequence` is inside `AuthInfo` |
| A malicious response cannot crash the guest | Bounded reads, and fuzzed parsers — see `docs/fuzzing.md` |

## What is not defended, and is someone else's job

- **Whether the signer is authorised at all.** That is the enclave's policy and
  attestation, not this library's.
- **Chain state being what the node says it is.** Verifying that needs a light
  client and ICS-23 proofs, which are explicitly out of launch scope. A caller
  that needs proof of balance cannot get it here.
- **IBC delivery.** A transfer that times out strands funds on the sending
  chain until a timeout proof is relayed. This library can tell you the
  transfer was delivered on the sending chain; it cannot tell you it arrived.
- **CosmWasm payload semantics.** An execute message is displayed as opaque. If
  the product needs the contract call explained, the contract's schema has to
  come from somewhere trusted, and there is no such source at launch.

## The mistakes most likely to be made here

1. Re-encoding a decoded `TxBody` and signing the result. It usually works,
   which is why it survives review.
2. Treating a code-0 `broadcast_tx_sync` as confirmation.
3. Incrementing `sequence` locally after a failure, when whether the chain
   consumed it depends on where the transaction failed.
4. Reading `cosmos1…` and `cosmosvaloper1…` as interchangeable, because the
   bytes underneath are identical.
5. Emitting a high-S signature and debugging the wrong layer when the node
   refuses it.
