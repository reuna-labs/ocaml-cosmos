module Client = Cosmos_rpc_flow.Make (Mirage_flow_unix.Fd)

type t = Client.t

let create = Client.create
let call = Client.call
let request = Client.request
let ( let* ) = Lwt.bind
let transport e = Error (Cosmos_rpc.Error.Transport e)

let connect ?limits ?(host_header = "localhost") ?path sockaddr domain =
  Lwt.catch
    (fun () ->
      let fd = Lwt_unix.socket domain Unix.SOCK_STREAM 0 in
      let* () = Lwt_unix.connect fd sockaddr in
      Lwt.return (Ok (Client.create ?limits ?path ~host:host_header fd)))
    (fun exn -> Lwt.return (transport (Printexc.to_string exn)))

let connect_tcp ?limits ?host_header ?path host port =
  Lwt.catch
    (fun () ->
      let* addrs =
        Lwt_unix.getaddrinfo host (string_of_int port)
          [ Unix.AI_SOCKTYPE Unix.SOCK_STREAM ]
      in
      match addrs with
      | [] ->
          Lwt.return
            (transport (Printf.sprintf "cannot resolve %s:%d" host port))
      | a :: _ ->
          let host_header = Option.value host_header ~default:host in
          connect ?limits ~host_header ?path a.Unix.ai_addr a.Unix.ai_family)
    (fun exn -> Lwt.return (transport (Printexc.to_string exn)))

let connect_unix ?limits ?host_header ?path socket_path =
  connect ?limits ?host_header ?path (Unix.ADDR_UNIX socket_path) Unix.PF_UNIX

let close _ = Lwt.return_unit
