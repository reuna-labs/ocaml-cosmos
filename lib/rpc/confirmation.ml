type t =
  | Unknown
  | In_mempool
  | Delivered of { height : int64 }
  | Final of { height : int64; depth : int }
  | Failed of { code : int; codespace : string; log : string }
