module Plain_client = Cosmos_rpc_flow.Make (Mirage_flow_unix.Fd)

module Tls_flow = struct
  type flow = Tls_lwt.Unix.t
  type error = string
  type write_error = string

  let pp_error = Fmt.string
  let pp_write_error = Fmt.string

  let read flow =
    let buffer = Bytes.create 16_384 in
    Lwt.catch
      (fun () ->
        Lwt.map
          (fun length ->
            let result : Cstruct.t Mirage_flow.or_eof =
              if length = 0 then `Eof
              else `Data (Cstruct.of_bytes (Bytes.sub buffer 0 length))
            in
            Ok result)
          (Tls_lwt.Unix.read flow buffer))
      (fun exn -> Lwt.return (Error (Printexc.to_string exn)))

  let write flow buffer =
    Lwt.catch
      (fun () ->
        Lwt.map
          (fun () -> Ok ())
          (Tls_lwt.Unix.write flow (Cstruct.to_string buffer)))
      (fun exn -> Lwt.return (Error (Printexc.to_string exn)))
end

module Secure_client = Cosmos_rpc_flow.Make (Tls_flow)

module Endpoint = struct
  type scheme = [ `Http | `Https ]

  type t = {
    scheme : scheme;
    host : string;
    port : int;
    path : string;
    host_header : string;
  }

  let has_scheme value =
    let marker = "://" in
    let marker_length = String.length marker in
    let value_length = String.length value in
    let rec go index =
      if index + marker_length > value_length then false
      else if String.sub value index marker_length = marker then true
      else go (index + 1)
    in
    go 0

  let bracket_ipv6 host =
    if String.contains host ':' then "[" ^ host ^ "]" else host

  let of_string value =
    let value = String.trim value in
    if value = "" then Error "endpoint is empty"
    else
      let legacy = not (has_scheme value) in
      let uri = Uri.of_string (if legacy then "http://" ^ value else value) in
      match (Uri.userinfo uri, Uri.fragment uri) with
      | Some _, _ -> Error "endpoint must not contain user information"
      | _, Some _ -> Error "endpoint must not contain a fragment"
      | None, None -> (
          let scheme =
            match Uri.scheme uri with
            | Some scheme -> String.lowercase_ascii scheme
            | None -> "http"
          in
          match scheme with
          | "http" | "https" -> (
              match Uri.host uri with
              | None -> Error "endpoint has no host"
              | Some host ->
                  let scheme = if scheme = "https" then `Https else `Http in
                  let default_port =
                    match (legacy, scheme) with
                    | true, `Http -> 26657
                    | false, `Http -> 80
                    | _, `Https -> 443
                  in
                  let port =
                    Option.value (Uri.port uri) ~default:default_port
                  in
                  if port < 1 || port > 65535 then
                    Error "endpoint port is outside 1..65535"
                  else
                    let path =
                      match Uri.path_and_query uri with
                      | "" -> "/"
                      | path -> path
                    in
                    let host_header =
                      if port = default_port then bracket_ipv6 host
                      else Printf.sprintf "%s:%d" (bracket_ipv6 host) port
                    in
                    Ok { scheme; host; port; path; host_header })
          | other -> Error ("unsupported endpoint scheme: " ^ other))

  let scheme endpoint = endpoint.scheme
  let host endpoint = endpoint.host
  let port endpoint = endpoint.port
  let path endpoint = endpoint.path
  let host_header endpoint = endpoint.host_header
end

type t =
  | Plain of Plain_client.t * Lwt_unix.file_descr
  | Secure of Secure_client.t * Tls_lwt.Unix.t

let create ?limits ?path ~host flow =
  Plain (Plain_client.create ?limits ?path ~host flow, flow)

let call client body =
  match client with
  | Plain (client, _) -> Plain_client.call client body
  | Secure (client, _) -> Secure_client.call client body

let request client method_ =
  match client with
  | Plain (client, _) -> Plain_client.request client method_
  | Secure (client, _) -> Secure_client.request client method_

let ( let* ) = Lwt.bind
let transport e = Error (Cosmos_rpc.Error.Transport e)

let connect ?limits ?(host_header = "localhost") ?path sockaddr domain =
  Lwt.catch
    (fun () ->
      let fd = Lwt_unix.socket domain Unix.SOCK_STREAM 0 in
      Lwt.catch
        (fun () ->
          let* () = Lwt_unix.connect fd sockaddr in
          Lwt.return (Ok (create ?limits ?path ~host:host_header fd)))
        (fun exn ->
          let* () = Lwt_unix.close fd in
          Lwt.return (transport (Printexc.to_string exn))))
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

let tls_config authenticator =
  let authenticator =
    match authenticator with
    | Some authenticator -> Ok authenticator
    | None -> Ca_certs.authenticator ()
  in
  match authenticator with
  | Error (`Msg message) -> Error message
  | Ok authenticator -> (
      match Tls.Config.client ~authenticator () with
      | Ok config -> Ok config
      | Error (`Msg message) -> Error message)

let connect_tls ?limits ?authenticator ?host_header ?path host port =
  match tls_config authenticator with
  | Error message -> Lwt.return (transport message)
  | Ok config ->
      Lwt.catch
        (fun () ->
          let* flow = Tls_lwt.Unix.connect config (host, port) in
          let host_header = Option.value host_header ~default:host in
          Lwt.return
            (Ok
               (Secure
                  ( Secure_client.create ?limits ?path ~host:host_header flow,
                    flow ))))
        (fun exn -> Lwt.return (transport (Printexc.to_string exn)))

let connect_uri ?limits ?authenticator ?host_header value =
  match Endpoint.of_string value with
  | Error message -> Lwt.return (transport message)
  | Ok endpoint -> (
      let host = Endpoint.host endpoint in
      let port = Endpoint.port endpoint in
      let path = Endpoint.path endpoint in
      let host_header =
        Option.value host_header ~default:(Endpoint.host_header endpoint)
      in
      match Endpoint.scheme endpoint with
      | `Http -> connect_tcp ?limits ~host_header ~path host port
      | `Https ->
          connect_tls ?limits ?authenticator ~host_header ~path host port)

let connect_unix ?limits ?host_header ?path socket_path =
  connect ?limits ?host_header ?path (Unix.ADDR_UNIX socket_path) Unix.PF_UNIX

let close = function
  | Plain (_, flow) ->
      Lwt.catch (fun () -> Lwt_unix.close flow) (fun _ -> Lwt.return_unit)
  | Secure (_, flow) ->
      Lwt.catch (fun () -> Tls_lwt.Unix.close flow) (fun _ -> Lwt.return_unit)
