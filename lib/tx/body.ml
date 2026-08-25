module Pb = Cosmos_proto.Cosmos_tx_v1beta1_tx.Cosmos.Tx.V1beta1
module Any = Cosmos_proto.Google_protobuf_any.Google.Protobuf.Any

module Timestamp =
  Cosmos_proto.Google_protobuf_timestamp.Google.Protobuf.Timestamp

type t = {
  messages : Msg.t list;
  memo : string;
  timeout_height : int64;
  timeout_timestamp : int64;
  unordered : bool;
  extension_options : (string * string) list;
  non_critical_extension_options : (string * string) list;
  (* The bytes this body is. Set once, at construction or at decode, and
     handed back by to_bytes unchanged. *)
  source : string;
}

let messages t = t.messages
let memo t = t.memo
let timeout_height t = t.timeout_height
let timeout_timestamp t = t.timeout_timestamp
let unordered t = t.unordered
let extension_options t = t.extension_options
let non_critical_extension_options t = t.non_critical_extension_options
let to_bytes t = t.source

let is_approvable t =
  List.for_all Msg.is_approvable t.messages
  && t.extension_options = []
  && t.non_critical_extension_options = []

let ( let* ) = Result.bind

let any_pairs l =
  List.map (fun (a : Any.t) -> (a.type_url, Bytes.to_string a.value)) l

let make ~messages ?(memo = "") ?(timeout_height = 0L) ?(timeout_timestamp = 0L)
    ?(unordered = false) () =
  if messages = [] then
    Error
      "body: a transaction with no messages is valid protobuf and means nothing"
  else if unordered && timeout_timestamp = 0L then
    Error
      "body: unordered requires timeout_timestamp -- without a sequence, the \
       timestamp is the only bound on replay"
  else
    let* anys =
      List.fold_left
        (fun acc m ->
          let* acc = acc in
          let* url, value = Msg.to_any m in
          Ok ((url, value) :: acc))
        (Ok []) messages
    in
    let anys = List.rev anys in
    let pb : Pb.TxBody.t =
      {
        messages =
          List.map
            (fun (type_url, value) : Any.t ->
              { type_url; value = Bytes.of_string value })
            anys;
        memo;
        timeout_height;
        unordered;
        timeout_timestamp =
          (if timeout_timestamp = 0L then None
           else Some ({ seconds = timeout_timestamp; nanos = 0 } : Timestamp.t));
        extension_options = [];
        non_critical_extension_options = [];
      }
    in
    Ok
      {
        messages;
        memo;
        timeout_height;
        timeout_timestamp;
        unordered;
        extension_options = [];
        non_critical_extension_options = [];
        source = Wire.encode (module Pb.TxBody) pb;
      }

let of_bytes ~base source =
  let* (pb : Pb.TxBody.t) = Wire.decode (module Pb.TxBody) source in
  let messages =
    List.map
      (fun (a : Any.t) ->
        Msg.of_any ~base ~type_url:a.type_url ~value:(Bytes.to_string a.value))
      pb.messages
  in
  Ok
    {
      messages;
      memo = pb.memo;
      timeout_height = pb.timeout_height;
      timeout_timestamp =
        (match pb.timeout_timestamp with Some t -> t.seconds | None -> 0L);
      unordered = pb.unordered;
      extension_options = any_pairs pb.extension_options;
      non_critical_extension_options =
        any_pairs pb.non_critical_extension_options;
      (* Verbatim. The whole point. *)
      source;
    }
