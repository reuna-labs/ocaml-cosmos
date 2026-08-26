module Http = Http

module type FLOW = sig
  type flow
  type error
  type write_error

  val pp_error : error Fmt.t
  val pp_write_error : write_error Fmt.t
  val read : flow -> (Cstruct.t Mirage_flow.or_eof, error) result Lwt.t
  val write : flow -> Cstruct.t -> (unit, write_error) result Lwt.t
end

module Make (Flow : FLOW) = struct
  module Rpc = Cosmos_rpc

  type t = {
    flow : Flow.flow;
    host : string;
    path : string;
    limits : Http.limits;
    id : int ref;
  }

  let create ?(limits = Http.default_limits) ?(path = "/") ~host flow =
    { flow; host; path; limits; id = ref 0 }

  let transport fmt =
    Printf.ksprintf (fun s -> Error (Rpc.Error.Transport s)) fmt

  let transport_fmt fmt =
    Format.kasprintf (fun s -> Error (Rpc.Error.Transport s)) fmt

  let write t s =
    Lwt.bind
      (Flow.write t.flow (Cstruct.of_string s))
      (function
        | Ok () -> Lwt.return (Ok ())
        | Error e ->
            Lwt.return (transport_fmt "write failed: %a" Flow.pp_write_error e))

  (* Reads until the parser says the response is complete. A peer that stops
     sending mid-response ends the read rather than blocking for ever, because
     Flow.read reports the close. *)
  let read_response t =
    let rec go state =
      match Http.result state with
      | Some r -> Lwt.return (Ok r)
      | None ->
          Lwt.bind (Flow.read t.flow) (function
            | Ok (`Data cs) -> (
                match Http.feed state (Cstruct.to_string cs) with
                | Ok state -> go state
                | Error e -> Lwt.return (Error (Rpc.Error.Malformed e)))
            | Ok `Eof -> (
                (* A body with neither a length nor chunking ends at the close, so
               a clean EOF can be a complete response. Anything else is a
               truncation. *)
                match Http.result state with
                | Some r -> Lwt.return (Ok r)
                | None ->
                    Lwt.return (transport "connection closed mid-response"))
            | Error e ->
                Lwt.return (transport_fmt "read failed: %a" Flow.pp_error e))
    in
    go (Http.start t.limits)

  let call t body =
    Lwt.bind
      (write t (Http.request ~host:t.host ~path:t.path body))
      (function
        | Error _ as e -> Lwt.return e
        | Ok () ->
            Lwt.bind (read_response t) (function
              | Error _ as e -> Lwt.return e
              | Ok (r : Http.response) ->
                  (* A non-2xx status is reported as a transport failure rather than
               parsed: CometBFT answers JSON-RPC errors with 200 and a body, so
               a non-2xx means something in front of the node, not the node. *)
                  if r.status < 200 || r.status >= 300 then
                    Lwt.return (transport "HTTP %d" r.status)
                  else Lwt.return (Ok r.body)))

  let request t m =
    incr t.id;
    Lwt.bind
      (call t (Rpc.Codec.request ~id:!(t.id) m))
      (function
        | Error _ as e -> Lwt.return e
        | Ok body -> Lwt.return (Rpc.Codec.response m body))
end
