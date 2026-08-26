(** The signer transcript.

    Binds the bytes a signature will cover to the meaning a human was shown and
    to the policy that approved it, under one versioned envelope.

    The binding is structural rather than procedural: the intent is derived from
    the payload bytes, the rendering from the intent, and an approval cannot be
    built except from a review that the policy passed. See {!Transcript}. *)

module Canonical = Canonical
module Transcript = Transcript
