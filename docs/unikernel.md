# Running as a unikernel

Two claims. The first runs on every commit; the second needs the Solo5
toolchain and is run by hand.

## Structural: the offline closure contains no I/O, and no GMP

`validation/solo5/unikernel.exe` links `cosmos-types`, `cosmos-crypto`,
`cosmos-proto`, `cosmos-tx`, `cosmos-rpc` and the `cosmos` umbrella, and **no
transport**.

```sh
OPAMSWITCH=reuna-5.5 opam exec -- ./test/no_io_guard.sh
```

The script checks two properties from the declared dependencies, then proves
the second one structurally by linking:

- **No I/O.** No offline package names `unix`, `threads`, `lwt`, `cohttp`,
  `conduit`, `mirage-flow*` or a clock, directly or through another package
  here.
- **No `zarith`, and therefore no GMP.** This one is easy to lose and invisible
  when you do: the code still builds, the duniverse simply stops locking. The
  way it would arrive is `mirage-crypto-blockchain`, which is the natural
  package to reach for when adding public-key recovery — and Cosmos does not
  need recovery, because the public key travels in `SignerInfo`. Both names are
  on the forbidden list.

The guard is not decorative. Adding `"zarith"` to `cosmos-types.opam` and
re-running reports five failures, one per package that transitively depends on
it, which is the behaviour it exists for.

The flow transports are checked separately and against a different list: they
are allowed Lwt and a flow, and are not allowed anything that assumes a host
operating system or a TCP stack. `cosmos-rpc-unix` is the deliberate exception.

## Actual: a Solo5 guest, booted

`validation/solo5-image/` is not written yet — it is G10 L5 work. When it is,
it will be simpler than `ocaml-tron`'s, which has to cross-compile GMP and
zarith before it can build an image. This closure has neither, so the image is
the OCaml code and `mirage-crypto-ec`'s C stubs.

## Why the transports are functors over `Mirage_flow.S`

Not a stylistic choice. The confidential Solo5 targets forbid `NET_BASIC`
outright, and `sptmac` has no networking at all, so a vsock is the only
transport available there. A client functorised over an HTTP library assumes a
TCP stack and cannot reach one; a client functorised over a flow can. TLS
composes as `Tls_mirage.Make` over the same signature.

The same reasoning is why `cosmos-rpc-grpc` does not use `h2-mirage`: that
package would do the functorising and pull roughly 48 packages doing it —
`conduit-mirage`, `tcpip`, `tls-mirage`, `x509`, `dns-client`, `vchan`,
`xenstore` — because it assumes a stack. What `h2` needs from a transport is
`Gluten_lwt.IO`, four functions, so those are implemented over a flow directly.
`ocaml-tron` reached this conclusion first and its `lib/rpc_grpc/io_of_flow.ml`
is the reference.
