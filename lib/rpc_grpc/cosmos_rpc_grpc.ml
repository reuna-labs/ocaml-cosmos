module Io_of_flow = Io_of_flow
module Method = Method_grpc
module Simulation = Simulation

module type FLOW = Io_of_flow.FLOW

module Make (F : FLOW) = struct
  module Io = Io_of_flow.Make (F)
  module Runtime = Gluten_lwt.Client (Io)
  module H2_client = H2_lwt.Client (Runtime)

  type t = { conn : H2_client.t; socket : Io.socket; scheme : string }

  let create ?(scheme = "http") flow =
    let socket = Io.create flow in
    Lwt.bind
      (H2_client.create_connection ~error_handler:(fun _ -> ()) socket)
      (fun conn -> Lwt.return { conn; socket; scheme })

  let flow t = Io.flow t.socket
  let shutdown t = H2_client.shutdown t.conn

  (* gRPC status codes are the application's answer, so they map to Abci rather
     than to a transport failure -- the node replied, and the reply was no. The
     codespace is "grpc" so a reader can tell where the number came from: gRPC
     code 5 and ABCI code 5 mean entirely different things. *)
  let status_name : Grpc.Status.code -> string = function
    | Grpc.Status.OK -> "OK"
    | Cancelled -> "CANCELLED"
    | Unknown -> "UNKNOWN"
    | Invalid_argument -> "INVALID_ARGUMENT"
    | Deadline_exceeded -> "DEADLINE_EXCEEDED"
    | Not_found -> "NOT_FOUND"
    | Already_exists -> "ALREADY_EXISTS"
    | Permission_denied -> "PERMISSION_DENIED"
    | Resource_exhausted -> "RESOURCE_EXHAUSTED"
    | Failed_precondition -> "FAILED_PRECONDITION"
    | Aborted -> "ABORTED"
    | Out_of_range -> "OUT_OF_RANGE"
    | Unimplemented -> "UNIMPLEMENTED"
    | Internal -> "INTERNAL"
    | Unavailable -> "UNAVAILABLE"
    | Data_loss -> "DATA_LOSS"
    | Unauthenticated -> "UNAUTHENTICATED"

  let call t (m : 'a Method.t) =
    let handler =
      Grpc_lwt.Client.Rpc.unary ~f:(fun response -> response) m.request
    in
    Lwt.bind
      (Grpc_lwt.Client.call ~service:m.service ~rpc:m.rpc ~scheme:t.scheme
         ~handler
         ~do_request:(H2_client.request t.conn ~error_handler:(fun _ -> ()))
         ())
      (function
        | Error status ->
            (* An HTTP/2 status means the request never reached the application,
             which is the same distinction the JSON-RPC client draws between an
             envelope error and an ABCI one. *)
            Lwt.return
              (Error
                 (Cosmos_rpc.Error.Rpc
                    {
                      code = H2.Status.to_code status;
                      message = "gRPC request rejected at the HTTP/2 layer";
                    }))
        | Ok (body, status) -> (
            match Grpc.Status.code status with
            | Grpc.Status.OK -> (
                match body with
                | None ->
                    Lwt.return
                      (Error
                         (Cosmos_rpc.Error.Malformed
                            "gRPC returned OK with no message"))
                | Some bytes -> Lwt.return (m.decode bytes))
            | code ->
                Lwt.return
                  (Error
                     (Cosmos_rpc.Error.Abci
                        {
                          code = Grpc.Status.int_of_code code;
                          codespace = "grpc";
                          log =
                            (status_name code
                            ^
                            match Grpc.Status.message status with
                            | Some m when m <> "" -> ": " ^ m
                            | _ -> "");
                        }))))
end
