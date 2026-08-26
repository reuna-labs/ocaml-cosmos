(** The typed, transport-independent client.

    Every method is pure: a request is bytes to send, a response is bytes to
    read, and the transport is a module type. That is what lets the same code
    run over a Unix file descriptor and a Solo5 vsock without changing. *)

module Error = Error
module Json = Json
module Method = Method
module Codec = Codec
module Query = Query
module Fees = Fees
module Confirmation = Confirmation
module Submission = Submission
module Provider = Provider
