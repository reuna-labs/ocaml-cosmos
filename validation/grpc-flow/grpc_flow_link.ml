(* gRPC over two in-memory buffers.

   No file descriptor, no address, no stack. What is being checked is the link:
   that Grpc_lwt, H2 and Gluten compose over a flow this program invented.

   It does not speak to a server. Driving a real HTTP/2 conversation would mean
   writing one, and the thing at risk here is the dependency closure -- if
   h2-mirage had crept in, this would not build at all. The wire behaviour is
   the live smoke's job. *)

module Buffer_flow = struct
  type flow = { mutable to_read : string list; written : Buffer.t }
  type error = |
  type write_error = |

  let pp_error : error Fmt.t = fun _ppf -> function _ -> .
  let pp_write_error : write_error Fmt.t = fun _ppf -> function _ -> .

  let read t =
    match t.to_read with
    | [] -> Lwt.return (Ok `Eof)
    | c :: rest ->
        t.to_read <- rest;
        Lwt.return (Ok (`Data (Cstruct.of_string c)))

  let write t cs =
    Buffer.add_string t.written (Cstruct.to_string cs);
    Lwt.return (Ok ())
end

module Client = Cosmos_rpc_grpc.Make (Buffer_flow)

let () =
  let flow = { Buffer_flow.to_read = []; written = Buffer.create 256 } in
  let client = Lwt_main.run (Client.create flow) in
  (* The methods encode without a connection: the request bytes are a pure
     function of the arguments, which is what lets them be compared against the
     JSON-RPC path's. *)
  let addr =
    Result.get_ok
      (Cosmos_types.Address.of_bech32 ~base:"cosmos"
         "cosmos1w508d6qejxtdg4y5r3zarvary0c5xw7k6ah60c")
  in
  let account = Cosmos_rpc_grpc.Method.account ~base:"cosmos" addr in
  let denom = Result.get_ok (Cosmos_types.Denom.of_string "uatom") in
  let balance = Cosmos_rpc_grpc.Method.balance ~base:"cosmos" addr ~denom in
  let simulate = Cosmos_rpc_grpc.Method.simulate ~tx_bytes:"\x0a\x00" in
  List.iter
    (fun (name, service, rpc, request) ->
      Printf.printf "%-10s %s/%s  request %d bytes\n" name service rpc
        (String.length request))
    [
      ("account", account.service, account.rpc, account.request);
      ("balance", balance.service, balance.rpc, balance.request);
      ("simulate", simulate.service, simulate.rpc, simulate.request);
    ];
  (* HTTP/2 was set up over the buffers: gluten, h2 and grpc all linked. *)
  Printf.printf
    "\nHTTP/2 handshake wrote %d bytes to a flow that is not a socket\n"
    (Buffer.length flow.Buffer_flow.written);
  Lwt_main.run (Client.shutdown client);
  print_endline "no h2-mirage, no conduit, no tcpip, no dns-client."
