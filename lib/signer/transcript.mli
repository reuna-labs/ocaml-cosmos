(** What was asked, what was shown, and what was approved.

    {2 The property this exists for}

    A signer must not be able to display one transaction and sign another. Most
    designs make that a rule and then rely on care. Here it is structural, in
    three steps:

    - the {b intent} is derived by decoding the payload bytes — the same bytes
      the signature will cover — and never from anything the caller says it is
      building;
    - the {b rendering} shown to a human is derived from that intent;
    - an {!approval} cannot be constructed except from a {!review}, and a
      {!review} cannot be constructed except by the policy passing.

    So "displayed X, signed Y" is not a mistake this API can express, and
    "approved without review" is not a value that exists.

    {2 What the transcript binds}

    Everything a later reader needs to judge the decision without rerunning it:
    the chain and account it was for, the exact bytes signed, the meaning
    derived from them, the words a human saw, the policy that accepted it, the
    freshness fields that bound it, and the measurement of the code that did the
    approving.

    {2 Freshness, and what is not solved here}

    A request carries a [nonce] and a [not_after]. {!check_freshness} compares
    [not_after] against a time the {i caller} supplies: nothing in this library
    reads a clock, because a signer that could would be one prompt away from
    extending its own window.

    The nonce is bound into the digest so that a replayed request is
    {i detectable}. Detecting it needs a record of nonces already used, which is
    state, and state belongs to whatever survives a restart — not to a pure
    library. This is deliberately half the anti-replay story; the other half is
    the enclave's, and pretending otherwise would be worse than saying so. *)

module Chain_id = Cosmos_types.Chain_id
module Intent = Cosmos_tx.Intent
module Policy = Cosmos_tx.Policy

type sign_mode = Direct | Legacy_amino_json

val sign_mode_to_string : sign_mode -> string

(** {2 The request} *)

type request

val request :
  chain_id:Chain_id.t ->
  account_number:int64 ->
  sequence:int64 ->
  sign_mode:sign_mode ->
  payload:string ->
  nonce:string ->
  not_after:int64 ->
  (request, string) result
(** [payload] is a serialized [SignDoc] in {b both} sign modes, and this is
    worth being explicit about.

    In {!Direct} the payload is also what gets signed. In {!Legacy_amino_json}
    it is not: the amino document is a different encoding of the same
    transaction, and the signer {i derives} it from this payload rather than
    accepting it. Taking amino bytes from the caller would mean reviewing one
    encoding and signing another, with nothing tying the two together — which is
    the exact failure the rest of this module exists to prevent, arriving
    through the front door.

    So the caller supplies one thing, the signer decides what that means, and
    {!signed_bytes} is what it actually signed.

    [not_after] is seconds since the Unix epoch. A request with no expiry is
    refused rather than treated as eternal: an unbounded signing request is one
    that can be held and used later. *)

val request_digest : request -> string
(** SHA-256 over the canonical encoding. Every field is bound; changing any of
    them changes this. *)

val check_freshness : request -> now:int64 -> (unit, string) result
(** [now] is supplied by the caller. See the note above about clocks. *)

(** {2 The review} *)

type review

val review :
  base:string -> policy:Policy.t -> request -> (review, string list) result
(** Decodes the payload, derives the intent, renders it, and puts it to the
    policy. [Error] carries every reason the policy refused, not the first.

    A payload that will not decode is refused too, and this is the case worth
    dwelling on: a signer that cannot read what it is being asked to sign has
    nothing to show a human, so approving it would be approving a hash. *)

val intent : review -> Intent.t

val signed_bytes : review -> string
(** What the signature will actually cover. The payload itself in {!Direct}; the
    amino document derived from it in {!Legacy_amino_json}. *)

val rendering : review -> string
(** The words a human is shown. A pure function of the payload, which is what
    makes the display and the signature the same claim. *)

val reviewed_request : review -> request

(** {2 The approval} *)

type approval

val sign :
  review ->
  key:Cosmos_crypto.private_key ->
  measurement:string ->
  (approval, string) result
(** Signs the payload the review covered. There is no path here that takes
    bytes: the only thing signable is something already reviewed.

    [measurement] identifies the code that approved — an enclave measurement, or
    whatever the deployment uses to answer "which signer was this". It is an
    input because this library cannot attest to itself. *)

val signature : approval -> Cosmos_crypto.signature

val signed_digest : approval -> string
(** SHA-256 of {!signed_bytes} — the digest the signature covers. Distinct from
    the payload digest in amino mode, which is why both are bound into the
    transcript. *)

val approval_digest : approval -> string
(** The value an attestation key signs, if the deployment has one. Binding an
    attested signature to this rather than to the payload is what lets a later
    reader see the meaning as well as the bytes. *)

val approved_review : approval -> review

val verify :
  approval -> key:Cosmos_crypto.public_key -> now:int64 -> (unit, string) result
(** Everything a reader can check without rerunning the decision: that the
    signature covers the payload the request named, that the rendering is the
    one the payload produces, and that the request had not expired at [now].

    This is what makes a transcript evidence rather than a log line. *)

val pp : Format.formatter -> approval -> unit
