let fail message =
  prerr_endline ("cosmos-address-of-key: " ^ message);
  exit 2

let hex_value = function
  | '0' .. '9' as c -> Char.code c - Char.code '0'
  | 'a' .. 'f' as c -> Char.code c - Char.code 'a' + 10
  | 'A' .. 'F' as c -> Char.code c - Char.code 'A' + 10
  | _ -> fail "stdin must contain a hexadecimal key"

let decode_hex value =
  let length = String.length value in
  if length <> 64 then fail "stdin must contain exactly 32 key bytes";
  String.init (length / 2) (fun index ->
      let offset = index * 2 in
      Char.chr
        ((hex_value value.[offset] lsl 4) lor hex_value value.[offset + 1]))

let read_stdin () =
  let input = Buffer.create 64 in
  (try
     while true do
       Buffer.add_string input (input_line stdin)
     done
   with End_of_file -> ());
  String.trim (Buffer.contents input)

let () =
  let secret = read_stdin () |> decode_hex in
  let private_key =
    match Cosmos_crypto.private_key_of_bytes secret with
    | Ok key -> key
    | Error _ -> fail "invalid secp256k1 private key"
  in
  let public_key = Cosmos_crypto.public_key_of_private private_key in
  let address =
    match
      Cosmos_types.Address.of_bytes Cosmos_types.Prefix.cosmos
        (Cosmos_crypto.address_bytes public_key)
    with
    | Ok address -> address
    | Error _ -> fail "could not derive account address"
  in
  print_endline (Cosmos_types.Address.to_bech32 address)
