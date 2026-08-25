type kind = Account | Validator | Consensus
type t = { base : string; kind : kind; hrp : string }

(* Bech32 allows a human-readable part of 1..83 printable ASCII characters.
   This is deliberately narrower -- see the .mli. 77 leaves room for the
   seven characters of "valoper". *)
let max_base_length = 77

let suffix = function
  | Account -> ""
  | Validator -> "valoper"
  | Consensus -> "valcons"

let well_formed_base base =
  let n = String.length base in
  if n = 0 then Error "prefix: the base prefix is empty"
  else if n > max_base_length then
    Error
      (Printf.sprintf "prefix: base prefix is %d characters, the maximum is %d"
         n max_base_length)
  else if
    not
      (String.for_all
         (fun c -> (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'))
         base)
  then Error "prefix: base prefix must be lower-case letters and digits"
  else Ok ()

(* A base that already ends in one of the suffixes cannot be told apart from
   another chain's derived prefix, so it is refused at construction rather
   than producing an address that two chains would both claim. *)
let ends_with s suffix =
  let n = String.length s and m = String.length suffix in
  m <= n && String.sub s (n - m) m = suffix

let unambiguous_base base =
  if ends_with base "valoper" || ends_with base "valcons" then
    Error
      (Printf.sprintf
         "prefix: base prefix %S already ends in a derived suffix, which would \
          be ambiguous"
         base)
  else Ok ()

let make ~base kind =
  match well_formed_base base with
  | Error _ as e -> e
  | Ok () -> (
      match unambiguous_base base with
      | Error _ as e -> e
      | Ok () -> Ok { base; kind; hrp = base ^ suffix kind })

let of_hrp ~base hrp =
  match well_formed_base base with
  | Error _ as e -> e
  | Ok () -> (
      match unambiguous_base base with
      | Error _ as e -> e
      | Ok () -> (
          let candidates = [ Account; Validator; Consensus ] in
          let matching =
            List.find_opt (fun k -> base ^ suffix k = hrp) candidates
          in
          match matching with
          | Some kind -> Ok { base; kind; hrp }
          | None ->
              Error
                (Printf.sprintf
                   "prefix: %S is not an address prefix of the %S chain" hrp
                   base)))

let to_string t = t.hrp
let base t = t.base
let kind t = t.kind
let equal a b = String.equal a.hrp b.hrp
let cosmos = { base = "cosmos"; kind = Account; hrp = "cosmos" }
