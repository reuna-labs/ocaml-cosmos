type t =
  | Send
  | Multi_send
  | Ibc_transfer
  | Wasm_execute
  | Unknown of { type_url : string; value : string }
