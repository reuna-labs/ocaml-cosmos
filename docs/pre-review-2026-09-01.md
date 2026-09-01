# Defensive pre-review — 2026-09-01

Status: **maintainer pre-review, not an audit and not independent assurance.**

This pass prepared commit
`0d3c8c69d526722f7e75a8ea001f86e5f8130cd9` for an independent reviewer. It
combined manual tracing of the signing and submission paths, an exception and
unsafe-operation inventory, the hermetic test/conformance suite, the no-I/O
link guard, bounded Crowbar runs, and construction of instrumented AFL targets.

## Result

One state-integrity defect was confirmed and fixed. No additional confirmed
signature-substitution or policy-bypass defect was found in this pass. That is
not a claim that none exists: the review was author-assisted, time-bounded, and
did not supply organizational independence.

| ID | Severity | State | Result |
| --- | --- | --- | --- |
| PR-01 | Medium | Fixed in baseline | A non-retryable late error could replace a terminal `Delivered` or `Rejected` outcome with `Gave_up`. `Submission.on_error` now treats every `Done` state as absorbing; a deterministic regression and adversarial event-sequence fuzz property cover it. |

PR-01 did not change signed or broadcast bytes. It could corrupt the caller's
record of a completed transaction, which is security-relevant where accounting
or retry decisions depend on that record.

## Paths traced

- `SignDoc` inner-byte retention through Direct signing and `TxRaw` framing.
- Amino bytes derived from decoded body/auth-info rather than caller-supplied
  Amino JSON.
- `Any` decoding, intent derivation, signer-count and extension-option checks,
  and policy refusal paths.
- Request chain/account/sequence binding, nonce/expiry representation,
  measurement binding, signature normalization, and transcript verification.
- CheckTx, DeliverTx, ambiguous broadcast, account refresh, polling, restart,
  and completion transitions.
- Protobuf/JSON exception containment, HTTP body limits, gRPC mapping, endpoint
  parsing, certificate roots, TLS name selection, and the offline link closure.

## Questions deliberately left for independent review

These are review prompts, not confirmed vulnerabilities:

- Prove Amino inline-JSON equivalence with the pinned Go SDK for duplicate
  object keys, number spellings, control characters, invalid UTF-8, and deeply
  nested values. Existing fixtures cover ordinary canonical payloads, not the
  complete hostile JSON grammar.
- Assess whether freshness is sufficiently hard to misuse. The pure library
  exposes `check_freshness`; trusted time and used-nonce persistence are
  intentionally supplied by the embedding signer rather than read internally.
- Check all size and recursion bounds across JSON, protobuf, HTTP, and gRPC as
  a whole. Per-response HTTP bytes are bounded, while decoded object depth and
  generated protobuf structure counts deserve independent resource-exhaustion
  analysis.
- Verify the Reuna secp256k1 and protobuf runtime forks at their pinned tags,
  including the previously fixed protobuf reader overflow. Reviewing only this
  repository is insufficient.
- Model concurrent submissions for one account. The state machine does not
  coordinate multiple callers; sequencing ownership belongs to the embedding
  service and must be explicit in its integration review.

## Evidence state at the time of writing

The ordinary suite, format check, bounded fuzz targets, and no-I/O guard passed
locally. The retained Linux AFL campaign then completed at commit
`9ab9a0e6b45a316cd1b6126cdd651f6f2e04090e`: all six targets ran for one hour,
executed 33,597,760 cases, and retained no crash or hang finding. Exact run,
statistics, and artifact digests are recorded in `docs/fuzzing.md`. No
independent reviewer has been engaged by this document.
