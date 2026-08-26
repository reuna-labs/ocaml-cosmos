module type MONAD = sig
  type 'a t

  val return : 'a -> 'a t
  val bind : 'a t -> ('a -> 'b t) -> 'b t
end

module type S = sig
  type 'a io
  type t

  val call : t -> string -> (string, Error.t) result io
end
