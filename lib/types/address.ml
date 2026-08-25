type t = { prefix : Prefix.t; bytes : string }

(* types/address/store_key.go:10 at the pinned revision. *)
let max_length = 255

(* types/bech32/bech32.go:21. Not BIP-173's 90, and passed explicitly at every
   call site so that no default can quietly reintroduce the smaller cap. *)
let bech32_max_length = 1023

let of_bytes prefix bytes =
  let n = String.length bytes in
  if n = 0 then Error "address: addresses cannot be empty"
  else if n > max_length then
    Error
      (Printf.sprintf "address: max length is %d bytes, got %d" max_length n)
  else Ok { prefix; bytes }

let to_bytes t = t.bytes
let prefix t = t.prefix
let length t = String.length t.bytes

let is_standard_length t =
  String.length t.bytes = 20 || String.length t.bytes = 32

let to_bech32 t =
  let groups =
    List.init (String.length t.bytes) (fun i -> Char.code t.bytes.[i])
  in
  (* 8 -> 5 with padding; types/bech32/bech32.go:11. *)
  match Web3_codec_bech32.convertbits ~pad:true groups ~from:8 ~into:5 with
  | None ->
      (* Unreachable: padding is on and every input byte is in range. *)
      invalid_arg "address: bit conversion failed on validated bytes"
  | Some data ->
      Web3_codec_bech32.encode ~max_length:bech32_max_length
        Web3_codec_bech32.Bech32
        ~hrp:(Prefix.to_string t.prefix)
        ~data

let of_bech32 ~base s =
  match Web3_codec_bech32.decode ~max_length:bech32_max_length s with
  | Error e -> Error ("address: " ^ e)
  | Ok (Web3_codec_bech32.Bech32m, _, _) ->
      (* The SDK calls btcutil's bech32.Decode, which is BIP-173 only. A bech32m
       checksum here is a string built for something else. *)
      Error "address: bech32m checksum, but Cosmos addresses are bech32"
  | Ok (Web3_codec_bech32.Bech32, hrp, data) -> (
      match Prefix.of_hrp ~base hrp with
      | Error _ as e -> e
      | Ok prefix -> (
          (* 5 -> 8 without padding; types/bech32/bech32.go:26. Refusing the
         padding is what rejects a string carrying leftover non-zero bits. *)
          match
            Web3_codec_bech32.convertbits ~pad:false data ~from:5 ~into:8
          with
          | None -> Error "address: trailing bits are not zero padding"
          | Some bytes ->
              let b = Bytes.create (List.length bytes) in
              List.iteri (fun i v -> Bytes.set b i (Char.chr v)) bytes;
              of_bytes prefix (Bytes.unsafe_to_string b)))

let equal a b = Prefix.equal a.prefix b.prefix && String.equal a.bytes b.bytes
let same_bytes a b = String.equal a.bytes b.bytes
