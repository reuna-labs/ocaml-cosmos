(* A flow made of two in-memory buffers.

   No file descriptor, no address, no stack. If cosmos-rpc-flow assumed any of
   those, this would not compile -- which is the point of the exercise, and is
   why it is a validation target rather than a test.

   It also lets the response be chosen, so the awkward shapes get exercised:
   a chunked body, a body split across reads, and a body larger than the
   limits allow. *)

module Buffer_flow = struct
  type flow = { mutable to_read : string list; written : Buffer.t }
  type error = |
  type write_error = |

  let pp_error : error Fmt.t = fun _ppf -> function _ -> .
  let pp_write_error : write_error Fmt.t = fun _ppf -> function _ -> .

  let read t =
    match t.to_read with
    | [] -> Lwt.return (Ok `Eof)
    | chunk :: rest ->
        t.to_read <- rest;
        Lwt.return (Ok (`Data (Cstruct.of_string chunk)))

  let write t cs =
    Buffer.add_string t.written (Cstruct.to_string cs);
    Lwt.return (Ok ())
end

module Client = Cosmos_rpc_flow.Make (Buffer_flow)

let http ?(status = 200) body =
  Printf.sprintf
    "HTTP/1.1 %d OK\r\n\
     Content-Type: application/json\r\n\
     Content-Length: %d\r\n\
     \r\n\
     %s"
    status (String.length body) body

let chunked body =
  (* Split into two chunks, to exercise the framing rather than just the
     happy single-chunk case. *)
  let half = String.length body / 2 in
  let a = String.sub body 0 half
  and b = String.sub body half (String.length body - half) in
  Printf.sprintf
    "HTTP/1.1 200 OK\r\n\
     Transfer-Encoding: chunked\r\n\
     \r\n\
     %x\r\n\
     %s\r\n\
     %x\r\n\
     %s\r\n\
     0\r\n\
     \r\n"
    (String.length a) a (String.length b) b

let run name chunks =
  let flow = { Buffer_flow.to_read = chunks; written = Buffer.create 256 } in
  let client = Client.create ~host:"node" flow in
  let result = Lwt_main.run (Client.request client Cosmos_rpc.Method.status) in
  (match result with
  | Ok (s : Cosmos_rpc.Method.status) ->
      Printf.printf "%-28s ok      chain=%s height=%Ld\n" name
        (Cosmos_types.Chain_id.to_string s.chain_id)
        s.latest_block_height
  | Error e ->
      Printf.printf "%-28s refused %s\n" name (Cosmos_rpc.Error.to_string e));
  (* The request that went out is a complete HTTP/1.1 POST. *)
  let sent = Buffer.contents flow.Buffer_flow.written in
  if name = "content-length" then
    Printf.printf "%-28s sent    %s\n" ""
      (String.concat " | "
         (String.split_on_char '\r' sent |> List.filteri (fun i _ -> i < 3)))

let status_body =
  {|{"jsonrpc":"2.0","id":1,"result":{"node_info":{"network":"cosmoshub-4","version":"0.38.22"},"sync_info":{"latest_block_height":"32675057","latest_block_time":"t","catching_up":false}}}|}

let () =
  print_endline "cosmos-rpc-flow, over two in-memory buffers:";
  run "content-length" [ http status_body ];
  (* Arriving one byte at a time: the parser is incremental, so this must give
     the same answer. *)
  run "byte at a time"
    (List.init
       (String.length (http status_body))
       (fun i -> String.make 1 (http status_body).[i]));
  run "chunked" [ chunked status_body ];
  run "chunked, split reads"
    (let s = chunked status_body in
     let third = String.length s / 3 in
     [
       String.sub s 0 third;
       String.sub s third third;
       String.sub s (2 * third) (String.length s - (2 * third));
     ]);
  run "truncated" [ String.sub (http status_body) 0 60 ];
  run "not http" [ "gibberish\r\n\r\n" ];
  run "http error" [ http ~status:502 "upstream is down" ];
  run "closed immediately" [];
  print_endline "";
  print_endline "no file descriptor, no address, no network stack."
