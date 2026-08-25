(* Deliberately empty.

   ocaml-protoc-plugin emits [module Google_api_annotations =
   Google_api_annotations] into the [Imported'modules] block of every generated
   file whose .proto says [import "google/api/annotations.proto"], which the
   Cosmos query and tx services all do. They use only its *option* --
   (google.api.http) -- which declares a grpc-gateway REST mapping and never
   appears on the wire. This library speaks CometBFT JSON-RPC and gRPC, not the
   REST gateway.

   So the reference has to resolve, and there is nothing for it to resolve to.
   ocaml-cometbft does the same for Gogo; nethsm's etcd_client did it first.

   There is a second reason this one is hand-written rather than generated.
   http.proto's doc comment lists the HTTP verbs inside braces separated by
   vertical bars, and OCaml reads that as the opening delimiter of a quoted
   string literal -- inside a comment, where nothing closes it -- so the
   generated file does not compile at all. This comment is worded around the
   same hazard.

   These files are hand-written and live outside gen/, which tools/gen-proto.sh
   wipes. *)
