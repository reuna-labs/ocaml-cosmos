(* The HTTP/1.1 parser's limits.

   Every length here is chosen by the peer. A Content-Length header can claim
   anything, a chunked body can go on for ever, and a header block can arrive
   without an end. The node is the adversary in docs/threat-model.md, so each
   of those is a bound rather than an allocation.

   The happy paths -- content-length, chunked, split reads -- are exercised by
   validation/flow, which drives the whole client over them. What is here is
   what should be refused. *)

module Http = Cosmos_rpc_flow.Http

let feed_all limits chunks =
  let rec go st = function
    | [] -> Ok st
    | c :: rest -> (
        match Http.feed st c with Ok st -> go st rest | Error _ as e -> e)
  in
  go (Http.start limits) chunks

let refused what r =
  match r with
  | Error _ -> ()
  | Ok _ -> Alcotest.failf "expected %s to be refused, it was accepted" what

let accepted what r =
  match r with
  | Ok st -> st
  | Error e -> Alcotest.failf "expected %s to be accepted, got %S" what e

let tiny = { Http.max_header_bytes = 256; max_body_bytes = 512 }

let response ?(headers = "") body =
  Printf.sprintf "HTTP/1.1 200 OK\r\nContent-Length: %d\r\n%s\r\n%s"
    (String.length body) headers body

let a_declared_body_over_the_limit_is_refused_before_it_arrives () =
  (* The header claims 10 MiB. Nothing has been sent yet, and it is already
     refused -- which is the property that matters: the refusal costs nothing. *)
  refused "a 10 MiB Content-Length"
    (feed_all tiny [ "HTTP/1.1 200 OK\r\nContent-Length: 10485760\r\n\r\n" ])

let an_endless_header_block_is_refused () =
  let endless =
    "HTTP/1.1 200 OK\r\n"
    ^ String.concat ""
        (List.init 200 (fun i -> Printf.sprintf "X-Pad-%d: filler\r\n" i))
  in
  refused "an endless header block" (feed_all tiny [ endless ])

let an_endless_chunked_body_is_refused () =
  let chunk = Printf.sprintf "%x\r\n%s\r\n" 100 (String.make 100 'a') in
  let stream =
    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
    :: List.init 20 (fun _ -> chunk)
  in
  refused "a chunked body past the cap" (feed_all tiny stream)

let a_body_that_grows_past_the_cap_is_refused_while_arriving () =
  (* No Content-Length and no chunking: the body ends at the close, so the only
     bound is the cap. *)
  let stream =
    "HTTP/1.1 200 OK\r\n\r\n" :: List.init 20 (fun _ -> String.make 100 'x')
  in
  refused "an unbounded body" (feed_all tiny stream)

let malformed_framing () =
  refused "no status line" (feed_all tiny [ "gibberish\r\n\r\n" ]);
  refused "a non-numeric status" (feed_all tiny [ "HTTP/1.1 nope OK\r\n\r\n" ]);
  refused "a negative Content-Length"
    (feed_all tiny [ "HTTP/1.1 200 OK\r\nContent-Length: -1\r\n\r\n" ]);
  refused "a non-numeric Content-Length"
    (feed_all tiny [ "HTTP/1.1 200 OK\r\nContent-Length: lots\r\n\r\n" ]);
  refused "a bad chunk size"
    (feed_all tiny
       [ "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nabc\r\n" ]);
  refused "an endless chunk-size line"
    (feed_all tiny
       [
         "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"
         ^ String.make 200 '0';
       ])

let what_is_within_the_limits_is_accepted () =
  (* The bound has to let ordinary responses through, or it is just a broken
     client. Exactly at the cap is fine; one past it is not. *)
  let at_cap = String.make tiny.Http.max_body_bytes 'y' in
  let st =
    accepted "a body exactly at the cap" (feed_all tiny [ response at_cap ])
  in
  (match Http.result st with
  | Some r ->
      Alcotest.(check int) "status" 200 r.status;
      Alcotest.(check int)
        "body length" tiny.Http.max_body_bytes (String.length r.body)
  | None -> Alcotest.fail "should be complete");
  refused "one byte past the cap"
    (feed_all tiny
       [ response (String.make (tiny.Http.max_body_bytes + 1) 'y') ])

let headers_are_case_insensitive () =
  (* A header name is case-insensitive, and a client that only matched the
     spelling CometBFT happens to use would break against a proxy. *)
  let st =
    accepted "CONTENT-LENGTH"
      (feed_all Http.default_limits
         [ "HTTP/1.1 200 OK\r\nCONTENT-LENGTH: 2\r\n\r\nhi" ])
  in
  match Http.result st with
  | Some r -> Alcotest.(check string) "body" "hi" r.body
  | None -> Alcotest.fail "should be complete"

let a_chunk_extension_is_ignored () =
  (* A chunk-size line may carry extensions after a semicolon. Failing on them
     would be refusing a legal response. *)
  let st =
    accepted "a chunk extension"
      (feed_all Http.default_limits
         [
           "HTTP/1.1 200 OK\r\n\
            Transfer-Encoding: chunked\r\n\
            \r\n\
            2;foo=bar\r\n\
            hi\r\n\
            0\r\n\
            \r\n";
         ])
  in
  match Http.result st with
  | Some r -> Alcotest.(check string) "body" "hi" r.body
  | None -> Alcotest.fail "should be complete"

let () =
  Alcotest.run "cosmos-http"
    [
      ( "bounds",
        [
          Alcotest.test_case "a declared body over the limit" `Quick
            a_declared_body_over_the_limit_is_refused_before_it_arrives;
          Alcotest.test_case "an endless header block" `Quick
            an_endless_header_block_is_refused;
          Alcotest.test_case "an endless chunked body" `Quick
            an_endless_chunked_body_is_refused;
          Alcotest.test_case "a body that grows past the cap" `Quick
            a_body_that_grows_past_the_cap_is_refused_while_arriving;
          Alcotest.test_case "and what fits is accepted" `Quick
            what_is_within_the_limits_is_accepted;
        ] );
      ( "framing",
        [
          Alcotest.test_case "malformed" `Quick malformed_framing;
          Alcotest.test_case "headers are case-insensitive" `Quick
            headers_are_case_insensitive;
          Alcotest.test_case "a chunk extension is ignored" `Quick
            a_chunk_extension_is_ignored;
        ] );
    ]
