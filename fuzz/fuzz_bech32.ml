module Address = Cosmos_types.Address
module Prefix = Cosmos_types.Prefix

let prefix =
  Crowbar.choose
    [
      Crowbar.const Prefix.cosmos;
      Crowbar.const
        (Result.get_ok (Prefix.make ~base:"cosmos" Prefix.Validator));
      Crowbar.const
        (Result.get_ok (Prefix.make ~base:"cosmos" Prefix.Consensus));
    ]

let valid_bytes =
  Crowbar.map [ Crowbar.bytes ] (fun bytes ->
      Crowbar.guard (String.length bytes > 0 && String.length bytes <= 255);
      bytes)

let () =
  Crowbar.add_test ~name:"arbitrary bech32 input never raises" [ Crowbar.bytes ]
    (fun input ->
      Crowbar.check
        (match Address.of_bech32 ~base:"cosmos" input with _ -> true))

let () =
  Crowbar.add_test ~name:"address bech32 round trip" [ prefix; valid_bytes ]
    (fun prefix bytes ->
      let address = Result.get_ok (Address.of_bytes prefix bytes) in
      let decoded =
        Result.get_ok
          (Address.of_bech32 ~base:"cosmos" (Address.to_bech32 address))
      in
      Crowbar.check (Address.equal address decoded))

let () =
  Crowbar.add_test ~name:"bech32m is never an account address"
    [ prefix; valid_bytes ] (fun prefix bytes ->
      let groups =
        List.init (String.length bytes) (fun i -> Char.code bytes.[i])
      in
      let data =
        Option.get
          (Web3_codec_bech32.convertbits ~pad:true groups ~from:8 ~into:5)
      in
      let encoded =
        Web3_codec_bech32.encode ~max_length:1023 Web3_codec_bech32.Bech32m
          ~hrp:(Prefix.to_string prefix) ~data
      in
      Crowbar.check (Result.is_error (Address.of_bech32 ~base:"cosmos" encoded)))
