(** Reading a node's JSON, defensively.

    Every accessor returns a result rather than raising, and every failure says
    which field was wrong. This is untrusted input: the node is the adversary in
    [docs/threat-model.md], and a decoder that raised on a missing field would
    turn a hostile response into a crash.

    {2 Numbers are strings, and only some of them}

    CometBFT marshals [int64] and [uint64] as JSON strings and [uint32] as JSON
    numbers, so a single response carries [{"height":"32675057","code":0}].
    Getting that backwards is the commonest way to write a decoder that works
    against the documentation and fails against a node, which is why
    {!int64_field} accepts only the string form and {!int_field} only the
    numeric one. *)

type t = Yojson.Safe.t

val parse : string -> (t, Error.t) result
val field : string -> t -> (t, Error.t) result

val opt_field : string -> t -> t option
(** [None] for both an absent field and an explicit [null]. CometBFT writes
    [null] where a field has no value rather than omitting it, so the two mean
    the same thing here. *)

val string_field : string -> t -> (string, Error.t) result

val int_field : string -> t -> (int, Error.t) result
(** A JSON number. This is what [uint32] fields such as [code] use. *)

val int64_field : string -> t -> (int64, Error.t) result
(** A JSON string holding a decimal integer. This is what [int64] and [uint64]
    fields such as [height] use. *)

val bool_field : string -> t -> (bool, Error.t) result

val base64_field : string -> t -> (string, Error.t) result
(** Decoded. [null] reads as the empty string, which is what a node sends for an
    absent [value]. *)
