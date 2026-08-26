(** The encoding a transcript is hashed over.

    Length-prefixed binary rather than JSON. A transcript digest is compared
    across two implementations that must agree exactly, and JSON offers a dozen
    ways to write the same document — key order, whitespace, number spelling,
    escaping. Amino JSON needs that fight because the SDK chose it; nothing here
    does.

    Every field is length-prefixed, so no concatenation of one field's contents
    with the next can be mistaken for a different split of the same bytes. That
    is the property a naive [a ^ b] separator scheme lacks: with a delimiter, a
    value containing the delimiter forges a different message. *)

type t

val create : string -> t
(** [create domain] starts a buffer under a domain separator. Two transcripts of
    different kinds never collide, because their bytes start differently. *)

val string : t -> string -> t
(** A length-prefixed field. *)

val int64 : t -> int64 -> t
val byte : t -> int -> t
val contents : t -> string

val digest : t -> string
(** SHA-256 of {!contents}. *)
