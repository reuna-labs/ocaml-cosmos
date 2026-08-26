module Chain_id = Cosmos_types.Chain_id

type 'a t = {
  name : string;
  params : (string * Json.t) list;
  decode : Json.t -> ('a, Error.t) result;
}

let map f t = { t with decode = (fun j -> Result.bind (t.decode j) f) }
let name t = t.name
let params t = t.params
let decode t = t.decode
let ( let* ) = Result.bind

(* ABCI query data is hex, and CometBFT has two parsers for it.
   
   The URI form -- GET /abci_query?data=0x... -- accepts a 0x prefix. The
   JSON-RPC form, which is the only one this client uses, unmarshals the
   parameter as bytes.HexBytes, and that rejects the prefix outright:
   
     "error converting json params to arguments: encoding/hex: invalid byte:
      U+0078 'x'"
   
   So: bare hex. This cost a live query to find, because both forms are hex and
   the difference does not appear in any response recorded over GET. *)
let hex s =
  String.concat ""
    (List.map
       (fun c -> Printf.sprintf "%02x" (Char.code c))
       (List.init (String.length s) (String.get s)))

let upper_hex s =
  String.concat ""
    (List.map
       (fun c -> Printf.sprintf "%02X" (Char.code c))
       (List.init (String.length s) (String.get s)))

(* --- status ------------------------------------------------------------- *)

type status = {
  chain_id : Chain_id.t;
  node_version : string;
  latest_block_height : int64;
  latest_block_time : string;
  catching_up : bool;
}

let status =
  {
    name = "status";
    params = [];
    decode =
      (fun j ->
        let* node_info = Json.field "node_info" j in
        let* sync_info = Json.field "sync_info" j in
        let* network = Json.string_field "network" node_info in
        let* node_version = Json.string_field "version" node_info in
        let* latest_block_height =
          Json.int64_field "latest_block_height" sync_info
        in
        let* latest_block_time =
          Json.string_field "latest_block_time" sync_info
        in
        let* catching_up = Json.bool_field "catching_up" sync_info in
        match Chain_id.of_string network with
        | Error e -> Error (Error.Malformed e)
        | Ok chain_id ->
            Ok
              {
                chain_id;
                node_version;
                latest_block_height;
                latest_block_time;
                catching_up;
              });
  }

(* --- abci_query --------------------------------------------------------- *)

type abci_response = { value : string; height : int64 }

let abci_query ~path ~data =
  {
    name = "abci_query";
    params = [ ("path", `String path); ("data", `String (hex data)) ];
    decode =
      (fun j ->
        let* response = Json.field "response" j in
        let* code = Json.int_field "code" response in
        let* codespace = Json.string_field "codespace" response in
        let* log = Json.string_field "log" response in
        if code <> 0 then Error (Error.Abci { code; codespace; log })
        else
          let* value = Json.base64_field "value" response in
          let* height = Json.int64_field "height" response in
          Ok { value; height });
  }

(* --- broadcast ---------------------------------------------------------- *)

type broadcast_result = {
  code : int;
  codespace : string;
  log : string;
  hash : string;
}

let broadcast_tx_sync bytes =
  {
    name = "broadcast_tx_sync";
    (* The transaction goes as base64 here, unlike the hex an abci_query takes.
       The two are not interchangeable and the node accepts neither in the
       other's place. *)
    params = [ ("tx", `String (Base64.encode_string bytes)) ];
    decode =
      (fun j ->
        let* code = Json.int_field "code" j in
        let* codespace = Json.string_field "codespace" j in
        let* log = Json.string_field "log" j in
        let* hash = Json.string_field "hash" j in
        (* A failed CheckTx is returned rather than raised: the caller needs
           the code and the log to decide whether to rebuild, and an error
           would throw them away. *)
        Ok { code; codespace; log; hash });
  }

(* --- tx ----------------------------------------------------------------- *)

type tx_result = {
  hash : string;
  height : int64;
  code : int;
  codespace : string;
  log : string;
  gas_wanted : int64;
  gas_used : int64;
}

let tx ~hash =
  {
    name = "tx";
    params = [ ("hash", `String (Base64.encode_string hash)) ];
    decode =
      (fun j ->
        let* hash = Json.string_field "hash" j in
        let* height = Json.int64_field "height" j in
        let* r = Json.field "tx_result" j in
        let* code = Json.int_field "code" r in
        let* codespace = Json.string_field "codespace" r in
        let* log = Json.string_field "log" r in
        let* gas_wanted = Json.int64_field "gas_wanted" r in
        let* gas_used = Json.int64_field "gas_used" r in
        Ok { hash; height; code; codespace; log; gas_wanted; gas_used });
  }

let _ = upper_hex
