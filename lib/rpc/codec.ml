let ( let* ) = Result.bind

let request ~id m =
  Yojson.Safe.to_string
    (`Assoc
       [
         ("jsonrpc", `String "2.0");
         ("id", `Int id);
         ("method", `String (Method.name m));
         ("params", `Assoc (Method.params m));
       ])

let response m body =
  let* j = Json.parse body in
  match Json.opt_field "error" j with
  | Some e ->
      (* An envelope error: the node refused the request. Its own fields are not
       guaranteed, so a missing message is reported rather than assumed. *)
      let code =
        match Json.int_field "code" e with Ok c -> c | Error _ -> 0
      in
      let message =
        match Json.string_field "message" e with
        | Ok m -> m
        | Error _ -> "(no message)"
      in
      let message =
        match Json.opt_field "data" e with
        | Some (`String d) -> message ^ ": " ^ d
        | _ -> message
      in
      Error (Error.Rpc { code; message })
  | None ->
      let* result = Json.field "result" j in
      Method.decode m result
