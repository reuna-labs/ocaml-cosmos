let ok = function Ok value -> value | Error message -> Alcotest.fail message

let pp_scheme formatter = function
  | `Http -> Format.pp_print_string formatter "http"
  | `Https -> Format.pp_print_string formatter "https"

let scheme_t = Alcotest.testable pp_scheme ( = )

let check_endpoint ~scheme:expected_scheme ~host ~port ~path ~host_header value
    =
  let endpoint = ok (Cosmos_rpc_unix.Endpoint.of_string value) in
  Alcotest.check scheme_t "scheme" expected_scheme
    (Cosmos_rpc_unix.Endpoint.scheme endpoint);
  Alcotest.(check string) "host" host (Cosmos_rpc_unix.Endpoint.host endpoint);
  Alcotest.(check int) "port" port (Cosmos_rpc_unix.Endpoint.port endpoint);
  Alcotest.(check string) "path" path (Cosmos_rpc_unix.Endpoint.path endpoint);
  Alcotest.(check string)
    "Host header" host_header
    (Cosmos_rpc_unix.Endpoint.host_header endpoint)

let https_provider () =
  check_endpoint ~scheme:`Https
    ~host:"rpc.provider-sentry-01.hub-testnet.polypore.xyz" ~port:443 ~path:"/"
    ~host_header:"rpc.provider-sentry-01.hub-testnet.polypore.xyz"
    "https://rpc.provider-sentry-01.hub-testnet.polypore.xyz"

let https_path_and_port () =
  check_endpoint ~scheme:`Https ~host:"provider.example" ~port:8443
    ~path:"/cosmos?archive=yes" ~host_header:"provider.example:8443"
    "https://provider.example:8443/cosmos?archive=yes"

let explicit_http () =
  check_endpoint ~scheme:`Http ~host:"127.0.0.1" ~port:80 ~path:"/status"
    ~host_header:"127.0.0.1" "http://127.0.0.1/status"

let legacy_cometbft () =
  check_endpoint ~scheme:`Http ~host:"127.0.0.1" ~port:26657 ~path:"/"
    ~host_header:"127.0.0.1" "127.0.0.1"

let rejects_unsafe_authority () =
  Alcotest.(check bool)
    "userinfo rejected" true
    (Result.is_error
       (Cosmos_rpc_unix.Endpoint.of_string "https://token@provider.example"));
  Alcotest.(check bool)
    "fragment rejected" true
    (Result.is_error
       (Cosmos_rpc_unix.Endpoint.of_string "https://provider.example/#not-sent"));
  Alcotest.(check bool)
    "non-HTTP scheme rejected" true
    (Result.is_error
       (Cosmos_rpc_unix.Endpoint.of_string "ftp://provider.example"))

let () =
  Alcotest.run "cosmos Unix endpoint"
    [
      ( "parse",
        [
          Alcotest.test_case "HTTPS provider" `Quick https_provider;
          Alcotest.test_case "HTTPS path and port" `Quick https_path_and_port;
          Alcotest.test_case "explicit HTTP" `Quick explicit_http;
          Alcotest.test_case "legacy CometBFT" `Quick legacy_cometbft;
          Alcotest.test_case "unsafe authority" `Quick rejects_unsafe_authority;
        ] );
    ]
