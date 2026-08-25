(* The seam between the generated protobuf types and the validated ones.

   Kept in one place because every conversion in it is a chance to lose a
   distinction the validated types exist to keep -- an address's prefix, an
   amount's width, a denomination's shape -- and because the generated names
   are long enough that inlining them would bury the logic. *)

module Pb = Ocaml_protoc_plugin
module Any = Cosmos_proto.Google_protobuf_any.Google.Protobuf.Any
module Pb_coin = Cosmos_proto.Cosmos_base_v1beta1_coin.Cosmos.Base.V1beta1.Coin
module Address = Cosmos_types.Address
module Amount = Cosmos_types.Amount
module Coin = Cosmos_types.Coin
module Denom = Cosmos_types.Denom

module type MESSAGE = sig
  type t

  val to_proto : t -> Pb.Writer.t
  val from_proto : Pb.Reader.t -> (t, [> Pb.Result.error ]) result
end

(* The runtime's error type is a polymorphic variant with no printer. Rendering
   it here rather than collapsing every failure to "malformed" is what makes a
   node's bad response diagnosable at the call site. *)
let describe = function
  | `Premature_end_of_input -> "truncated"
  | `Unknown_field_type n -> Printf.sprintf "unknown wire type %d" n
  | `Wrong_field_type (expected, got) ->
      Printf.sprintf "expected a %s field, got %s" expected got
  | `Illegal_value (what, _) -> Printf.sprintf "illegal value for %s" what
  | `Unknown_enum_value n -> Printf.sprintf "unknown enum value %d" n
  | `Unknown_enum_name n -> Printf.sprintf "unknown enum name %s" n
  | `Required_field_missing (n, name) ->
      Printf.sprintf "required field %d (%s) is missing" n name
  | _ -> "malformed"

let encode (type a) (module M : MESSAGE with type t = a) (v : a) =
  Pb.Writer.contents (M.to_proto v)

let decode (type a) (module M : MESSAGE with type t = a) (bytes : string) =
  (* from_proto returns a result and the underlying reader can also raise on
     malformed input; both are caught, because these bytes came from a node.
     The raising path is not hypothetical -- fuzzing ocaml-tron found a
     segfault in this runtime's reader, fixed in the vendored copy, and a
     library that assumes a result type is honoured has no defence if another
     turns up. *)
  match M.from_proto (Pb.Reader.create bytes) with
  | Ok v -> Ok v
  | Error e -> Error ("protobuf: " ^ describe e)
  | exception _ -> Error "protobuf: malformed"

(* --- coins ------------------------------------------------------------- *)

let coin_to_pb c : Pb_coin.t =
  {
    denom = Denom.to_string (Coin.denom c);
    amount = Amount.to_string (Coin.amount c);
  }

let coin_of_pb (c : Pb_coin.t) = Coin.of_strings ~denom:c.denom ~amount:c.amount

let rec coins_of_pb acc = function
  | [] -> Ok (List.rev acc)
  | c :: rest -> (
      match coin_of_pb c with
      | Error _ as e -> e
      | Ok c -> coins_of_pb (c :: acc) rest)

let coins_of_pb l = coins_of_pb [] l
let coins_to_pb l = List.map coin_to_pb l

(* --- addresses --------------------------------------------------------- *)

let address_of_bech32 ~base s = Address.of_bech32 ~base s
let address_to_bech32 = Address.to_bech32
