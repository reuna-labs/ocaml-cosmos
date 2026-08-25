# The build switch

This repository builds in the shared opam switch **`reuna-5.5`**. It does not
carry a local `_opam`. `ocaml-cardano/docs/switch.md` is where that switch was
first written down and `ocaml-tron/docs/switch.md` records what Tron added;
this file records what `ocaml-cosmos` adds, which is almost nothing.

## What it is

```
$ opam switch show
reuna-5.5
```

`ocaml-base-compiler.5.5.0`, holding the coordinated Reuna fork set: `digestif`,
`mirage-crypto{,-ec,-rng}`, `mirage`, `ocaml-solo5`, `solo5`,
`mirage-vsock-solo5`, the Nitrokey `cohttp`/`tls` forks, and the `web3-codec-*`
packages pinned from `../ocaml-web3-codec`. See the two files above for the
full table.

## Why 5.5.0

Not a preference. `ocaml-solo5` 1.3.4 declares `"ocaml" {>= "5.5" & < "5.6"}`,
so it is the only compiler that can cross-compile a unikernel against these
forks.

## The hazard

`reuna-5.5` is the opam **global default**. An `opam install` run from this
directory without an explicit `--switch` mutates the switch that builds
nethsm's confidential unikernels.

So, in this repository:

1. **Name the switch explicitly, always** — `--switch reuna-5.5`, or export
   `OPAMSWITCH=reuna-5.5`.
2. **Additive only.** Before installing anything, look:

   ```sh
   opam install --switch reuna-5.5 --deps-only --with-test --show-actions .
   ```

   The plan must contain **only `install` lines**. An upgrade, downgrade,
   removal *or recompile* of an existing root means stop: that root has
   consumers elsewhere in the tree, and they have to be checked before it moves.
3. **Never `opam upgrade`** here. Ever.

## What this repository needs

Everything, with one exception, was already installed by the Cardano and Tron
work: `digestif.dev` (the fork), `mirage-crypto-ec.dev`, `yojson`, `uri`,
`lwt` 6.1.2, `cstruct`, `mirage-flow`, `mirage-flow-unix`, `fmt`, `base64`,
`ptime`, `web3-codec-protobuf`, `h2`, `h2-lwt`, `gluten-lwt`, `faraday`,
`bigstringaf`, `grpc`, `grpc-lwt`, `alcotest`, `qcheck-core`,
`qcheck-alcotest`, `ocamlformat`, `mirage`, `solo5`, `ocaml-solo5`.

Added by this repository:

| Package | Where from | Why |
| --- | --- | --- |
| `web3-codec-bech32` | `../ocaml-web3-codec` | Bech32, sliced out of the umbrella for this repository. It depends on nothing at all, so the install is one package and no new pins. |

That is the whole delta, and it was verified additive before installing:

```
The following actions would be performed:
=== install 1 package
  ∗ web3-codec-bech32 0.1.0~alpha1 (pinned)
```

### What is deliberately absent

`mirage-crypto-blockchain` is **not** installed for this repository, and must
not be. It is what `ocaml-tron` uses for public-key recovery, and it carries
`zarith` and therefore GMP. Cosmos never recovers a key — the public key
travels in `SignerInfo` — so the whole closure here is GMP-free, which is what
keeps the unikernel duniverse small and the build free of a cross-compiled GMP
step. `test/no_io_guard.sh` asserts it.

`mirage-crypto-blockchain-core` is a different package with no `zarith` and
would be harmless; nothing here needs it either.

## The second switch: `web3-protoc`

Regenerating the protobuf bindings needs `ocaml-protoc-plugin` and a `protoc`.
Installing the plugin into `reuna-5.5` is **not** additive — it recompiles
`ocamlformat` and pulls a 23-package ppx cone, which is exactly the cone the
vendored runtime exists to avoid. It lives in its own switch:

```sh
opam switch create web3-protoc ocaml-base-compiler.5.5.0 --no-switch
opam install --switch web3-protoc ocaml-protoc-plugin.6.2.0
```

Generated sources are committed, so an ordinary build, and CI, never touch it.
The regeneration command is in `docs/protocol-pin.md`.
