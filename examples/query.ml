(* A read-only look at a live chain.
   
   Everything here is a query. Nothing is signed and nothing is broadcast,
   which is what makes it safe to point at mainnet -- and it is still worth
   running, because it is the only thing that exercises the Unix transport
   against a node rather than against a fixture.
   
   The signing smoke is deliberately not this program. That one needs a
   disposable key, a testnet, and a decision about where the key comes from,
   and bundling it with a harmless query would make the harmless thing look
   dangerous.
   
   usage:
     dune exec examples/query.exe -- [endpoint] [address] [host-header]
   
   defaults to a public Cosmos Hub node and the BIP-173 example address, which
   exists on mainnet and holds nothing worth having.
   
   The third argument exists because the Host header is not decoration. Anything
   in front of a node -- a CDN, a reverse proxy, a TLS terminator -- routes on
   it, and will answer 403 to a request whose Host is the address it was dialled
   at. It defaults to the host dialled, which is right for a node you connect to
   directly and wrong for one behind a proxy. *)

let ( let* ) = Lwt.bind
let default_endpoint = "https://cosmos-rpc.publicnode.com"
let default_address = "cosmos1w508d6qejxtdg4y5r3zarvary0c5xw7k6ah60c"

let show name = function
  | Ok v -> Printf.printf "%-16s %s\n" name v
  | Error e -> Printf.printf "%-16s -- %s\n" name (Cosmos_rpc.Error.to_string e)

let main endpoint address host_header =
  Printf.printf "querying %s%s\n\n" endpoint
    (match host_header with None -> "" | Some host -> " (Host: " ^ host ^ ")");
  let* client = Cosmos_rpc_unix.connect_uri ?host_header endpoint in
  match client with
  | Error e ->
      prerr_endline (Cosmos_rpc.Error.to_string e);
      Lwt.return 1
  | Ok client -> (
      let* status = Cosmos_rpc_unix.request client Cosmos_rpc.Method.status in
      (match status with
      | Error e -> show "status" (Error e)
      | Ok (s : Cosmos_rpc.Method.status) ->
          show "chain" (Ok (Cosmos_types.Chain_id.to_string s.chain_id));
          show "node" (Ok s.node_version);
          show "height" (Ok (Int64.to_string s.latest_block_height));
          show "catching up" (Ok (string_of_bool s.catching_up)));
      let base =
        (* The account prefix is the part of the address before the "1". *)
        match String.index_opt address '1' with
        | Some i -> String.sub address 0 i
        | None -> "cosmos"
      in
      match Cosmos_types.Address.of_bech32 ~base address with
      | Error e ->
          Printf.printf "\n%-16s -- %s\n" "address" e;
          Lwt.return 1
      | Ok addr ->
          Printf.printf "\n%s\n" address;
          let* account =
            Cosmos_rpc_unix.request client (Cosmos_rpc.Query.account ~base addr)
          in
          (match account with
          | Error e -> show "account" (Error e)
          | Ok (Cosmos_rpc.Query.Other { type_url }) ->
              show "account" (Ok type_url)
          | Ok (Cosmos_rpc.Query.Base a) ->
              show "account number" (Ok (Int64.to_string a.account_number));
              show "sequence" (Ok (Int64.to_string a.sequence));
              show "has pubkey" (Ok (string_of_bool a.has_public_key)));
          let denom = Result.get_ok (Cosmos_types.Denom.of_string "uatom") in
          let* balance =
            Cosmos_rpc_unix.request client
              (Cosmos_rpc.Query.balance ~base addr ~denom)
          in
          (match balance with
          | Error e -> show "balance" (Error e)
          | Ok c -> show "balance" (Ok (Cosmos_types.Coin.to_string c)));
          let* () = Cosmos_rpc_unix.close client in
          Lwt.return 0)

let () =
  let endpoint =
    if Array.length Sys.argv > 1 then Sys.argv.(1) else default_endpoint
  in
  let address =
    if Array.length Sys.argv > 2 then Sys.argv.(2) else default_address
  in
  let host_header =
    if Array.length Sys.argv > 3 then Some Sys.argv.(3) else None
  in
  exit (Lwt_main.run (main endpoint address host_header))
