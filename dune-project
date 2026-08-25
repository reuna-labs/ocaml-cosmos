(lang dune 3.6)

(name cosmos)

(version 0.1.0~alpha1)

(generate_opam_files true)

; Careful: the *.opam files are generated from this one, but cosmos.opam also
; carries a hand-maintained `pin-depends:` block that dune cannot express, kept
; alongside in cosmos.opam.template. Regenerating drops it from cosmos.opam,
; and the drop is silent -- the package still solves, just against released
; mirage-crypto instead of the fork that provides Secp256k1 (P256k1).
; Re-add it after any regeneration. ocaml-cardano, ocaml-tron, ocaml-bitcoin
; and ocaml-mpc carry the same hazard; ocaml-cometbft gave up on generation
; over it.

(implicit_transitive_deps false)

(source
 (github reuna-labs/ocaml-cosmos))

(license ISC)

(authors "Gil Bahat <bahat.gil@gmail.com>")

(maintainers "Gil Bahat <bahat.gil@gmail.com>")

; No zarith, and therefore no GMP, anywhere in this closure -- and none of the
; packages below may acquire one.
;
; That is not luck. Cosmos never recovers a public key from a signature: the
; key travels in SignerInfo, so the reference bignum backend in
; mirage-crypto-blockchain is not needed and mirage-crypto-ec's fiat-crypto
; P256k1 is the whole of the curve work. Address derivation is RIPEMD-160 over
; SHA-256, both in digestif. Bech32 is integer arithmetic. The protobuf runtime
; is base64 + ptime. ocaml-tron cannot make this claim (Base58 and public-key
; recovery both need zarith); ocaml-cardano can, for a different reason.
;
; Losing it is silent -- the code still builds, the unikernel duniverse just
; stops locking -- so test/no_io_guard.sh checks it from the declared
; dependencies, alongside the I/O rule.

(package
 (name cosmos-proto)
 (synopsis "Generated protobuf bindings for the Cosmos SDK wire types")
 (description
  "Bindings generated with ocaml-protoc-plugin from the .proto tree vendored at\nproto/, pinned to cosmos-sdk v0.55.0, ibc-go v11.2.0 and wasmd v0.70.3. The\ngenerated sources are committed, so building this package requires neither\nprotoc nor the plugin.\n\nDepends only on web3-codec-protobuf, whose closure is base64 + ptime, and in\nparticular not on unix, so it links into a MirageOS/Solo5 unikernel.\n\nThese are wire types, not a validated model. Every message in a TxBody is a\ngoogle.protobuf.Any that the generated code cannot narrow; narrowing it is\ncosmos-tx's job.")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (web3-codec-protobuf (>= 0.1.0~alpha1))))

(package
 (name cosmos-types)
 (synopsis "Validated primitive types for Cosmos SDK chains")
 (description
  "Bech32 account, validator and consensus addresses; coins and denominations;\nchain identifiers; transaction and block hashes; and the per-chain profile\nthat carries the bech32 prefix, fee denomination, minimum gas price and SDK\nversion.\n\nThe address is 20 or 32 raw bytes plus a prefix; its bech32 spelling is a\nrendering. cosmos1... and cosmosvaloper1... are the same bytes under\ndifferent prefixes, which is why the prefix is part of the type rather than\npart of the formatting.")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (web3-codec-bech32 (>= 0.1.0~alpha1))
  (digestif (>= 1.2.0))
  (alcotest :with-test)
  (qcheck-core :with-test)
  (qcheck-alcotest :with-test)))

(package
 (name cosmos-crypto)
 (synopsis "secp256k1 signing and address derivation for Cosmos SDK chains")
 (description
  "Signs the 32-byte SHA-256 digest of a serialized SignDoc and produces the\n64-byte r||s the SDK expects -- no recovery byte, because the public key\ntravels in SignerInfo.\n\nSignatures are normalised to low-S. The SDK rejects high-S as malleable and\nmirage-crypto-ec does not normalise, so this is a correctness requirement\nrather than a preference.\n\nCurve operations use mirage-crypto-ec's fiat-crypto P256k1 backend and are\nconstant time. Address derivation is RIPEMD-160 over SHA-256 of the\ncompressed public key, both from digestif. Ed25519 is verify-only: it is a\nvalidator key type, not an account signing path this library offers.\n\nNo RNG: nonces are RFC 6979 deterministic.")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (cosmos-types (= :version))
  (digestif (>= 1.2.0))
  (mirage-crypto-ec (>= 2.1.0))
  (alcotest :with-test)
  (qcheck-core :with-test)
  (qcheck-alcotest :with-test)))

(package
 (name cosmos-tx)
 (synopsis "Cosmos transaction construction, sign modes, intent and policy")
 (description
  "TxBody, AuthInfo, SignDoc and TxRaw; SIGN_MODE_DIRECT and\nSIGN_MODE_LEGACY_AMINO_JSON; the message allow-list; the fee model; and the\nbyte-derived intent layer with allow-list policies over it.\n\nSignDoc binds body_bytes and auth_info_bytes as opaque byte strings, and\nTxRaw carries those same bytes back out. They are retained, never re-encoded:\nprotobuf admits encodings that decode alike and re-encode differently, and a\nre-encode would change what the node is being asked to do.\n\nThe amino JSON writer is hand-written rather than built on a JSON library.\nIt is a canonical encoder over signed data -- sorted keys, no whitespace,\nomitted empty fields -- and keeping it here is what keeps yojson out of the\noffline closure.")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (cosmos-types (= :version))
  (cosmos-crypto (= :version))
  (cosmos-proto (= :version))
  (web3-codec-protobuf (>= 0.1.0~alpha1))
  (digestif (>= 1.2.0))
  (alcotest :with-test)
  (qcheck-core :with-test)
  (qcheck-alcotest :with-test)))

(package
 (name cosmos-rpc)
 (synopsis "Typed transport-independent CometBFT and Cosmos gRPC client")
 (description
  "The CometBFT JSON-RPC method catalogue, the SDK query and tx services, gas\nand fee estimation, a tagged confirmation state and the submission state\nmachine -- all pure. The transport is a module type.\n\nConfirmation is tagged, not boolean. A code-0 broadcast_tx_sync means the\ntransaction entered a mempool; delivery is a tx query returning code 0 at a\nheight, and finality is depth beyond that. Conflating the three is the\ncommonest way to report a failed transfer as a successful one.")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (cosmos-types (= :version))
  (cosmos-tx (= :version))
  (yojson (>= 2.0.0))
  (alcotest :with-test)))

(package
 (name cosmos-rpc-flow)
 (synopsis "CometBFT JSON-RPC over any Mirage_flow.S, including Solo5 vsock")
 (description
  "The HTTP/1.1 framing lives here as a pure parser and the client is a functor\nover Mirage_flow.S; this package owns the socket. Functorising over a flow\nrather than over an HTTP client is not a preference: the confidential Solo5\ntargets forbid NET_BASIC outright, and sptmac has no networking at all, so\nvsock is the only transport available there. TLS composes as Tls_mirage.Make\nover the same signature.")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (cosmos-rpc (= :version))
  (lwt (>= 5.6.0))
  (cstruct (>= 6.0.0))
  (mirage-flow (>= 4.0.0))
  fmt
  (alcotest :with-test)))

(package
 (name cosmos-rpc-grpc)
 (synopsis "Cosmos gRPC query and tx services over any Mirage_flow.S")
 (description
  "cosmos.tx.v1beta1.Service, cosmos.auth.v1beta1.Query and\ncosmos.bank.v1beta1.Query over gRPC, decoding into the same typed values the\nJSON-RPC client produces, so that the two wire paths can be compared rather\nthan merely coexisting.\n\nFunctorised over the same flow signature as cosmos-rpc-flow. Not h2-mirage:\nthat package would do the functorising, but its closure assumes a full\nnetwork stack -- conduit-mirage, tcpip, tls, x509, dns-client -- and the\nconfidential Solo5 targets have a vsock instead. What h2 needs from a\ntransport is Gluten_lwt.IO, which is four functions, so this implements those\nover a flow directly, following ocaml-tron.")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (cosmos-types (= :version))
  (cosmos-tx (= :version))
  (cosmos-proto (= :version))
  (cosmos-rpc (= :version))
  (web3-codec-protobuf (>= 0.1.0~alpha1))
  grpc
  grpc-lwt
  (h2 (>= 0.13.0))
  (h2-lwt (>= 0.13.0))
  gluten-lwt
  faraday
  bigstringaf
  (lwt (>= 5.6.0))
  (cstruct (>= 6.0.0))
  (mirage-flow (>= 4.0.0))
  fmt
  (alcotest :with-test)))

(package
 (name cosmos-rpc-unix)
 (synopsis "Unix transport for the CometBFT JSON-RPC client")
 (description
  "Cardano's and Tron's arrangement: this is Cosmos_rpc_flow.Make applied to a\nUnix file descriptor and nothing else, so the Unix path and the unikernel\npath are the same implementation with a different flow underneath.\n\nThe guarded live-network executable ships in this package: it is the only\nthing here that signs with a real key and touches a network, and it needs a\nUnix transport to do either.")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (cosmos-rpc (= :version))
  (cosmos-rpc-flow (= :version))
  (cosmos-tx (= :version))
  (cosmos-crypto (= :version))
  (lwt (>= 5.6.0))
  (mirage-flow-unix (>= 4.0.0))
  (uri (>= 4.2.0))
  (alcotest :with-test)))

(package
 (name cosmos)
 (synopsis "Pure OCaml Cosmos SDK client and signer library")
 (description
  "The offline surface: types, crypto, generated wire bindings, transaction\nconstruction and the typed RPC protocol. Transports are deliberately absent\n-- cosmos-rpc-flow, cosmos-rpc-grpc and cosmos-rpc-unix are separate packages\nso that a consumer linking this one takes on no Lwt, no Unix and no socket.")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.6))
  (cosmos-types (= :version))
  (cosmos-crypto (= :version))
  (cosmos-proto (= :version))
  (cosmos-tx (= :version))
  (cosmos-rpc (= :version))
  (alcotest :with-test)
  (qcheck-core :with-test)
  (qcheck-alcotest :with-test)
  ; fuzz/ builds against this. A real campaign needs an AFL-instrumented
  ; switch; see docs/fuzzing.md.
  (crowbar :with-test)))
