#!/bin/sh
#
# The offline packages must stay free of I/O.
#
# Checks *declared* dependencies rather than grepping sources. That is what
# actually determines what a unikernel links: a file that never writes `Unix.`
# still drags in unix if its package declares it, and a file that mentions Unix
# in a comment does not.
#
# It checks two properties, not one. The I/O rule is the usual one. The second
# is that this closure carries no zarith, and therefore no GMP: Cosmos never
# recovers a public key from a signature, so the reference bignum backend is
# not needed, and its absence is what keeps a unikernel's duniverse small. That
# property is invisible at compile time -- the code builds either way, the
# duniverse just stops locking -- so it has to be asserted here.
#
# Three checks, and the last is the one that would catch a dependency acquiring
# unix or zarith without this repository changing:
#
#   1. No offline package's `depends:` names a forbidden package, directly or
#      through another package in this repository.
#   2. The flow transports name nothing that assumes a host OS or a TCP stack.
#   3. The validation unikernel, which links the offline closure and no
#      transport, still links. If the closure grows a Unix dependency anywhere
#      -- including inside a package we do not own -- this stops building.
#
# Run from the repository root. Exits non-zero on the first violation.

set -eu

DUNE="${DUNE:-dune}"

# Everything a signature covers, plus the transport-free RPC layer. Deliberately
# not the transports: those own a socket, which is their job.
OFFLINE="cosmos-types cosmos-crypto cosmos-proto cosmos-tx cosmos-rpc cosmos"

# The transports that must still reach a Solo5 vsock. They are allowed Lwt and
# a flow; they are not allowed anything that assumes a host operating system or
# a TCP stack. cosmos-rpc-unix is deliberately absent -- being Unix-specific is
# what it is for.
FLOW_TRANSPORTS="cosmos-rpc-flow cosmos-rpc-grpc"

# unix and threads are the direct hazards. lwt, cohttp, conduit and
# mirage-flow* are listed because they are the usual ways unix arrives without
# anyone naming it.
#
# zarith is on this list for a different reason -- it is not I/O. It is the
# GMP rule: see the header. mirage-crypto-blockchain is named alongside it
# because that package is how zarith would arrive here without anyone typing
# "zarith", and reaching for it is the natural mistake to make when adding
# public-key recovery that Cosmos does not need. mirage-crypto-blockchain-core
# is a different package and is fine: it has no zarith.
FORBIDDEN="unix threads lwt cohttp cohttp-lwt cohttp-lwt-unix conduit conduit-lwt
conduit-lwt-unix mirage-flow mirage-flow-unix mirage-crypto-rng-unix ptime-clock
mtime-clock ptime.clock.os core_unix async
zarith mirage-crypto-blockchain web3-codec-basen web3-codec-base58 web3-codec"

# What a flow transport may not have. Lwt and mirage-flow are fine here; a host
# operating system or a network stack is not. h2-mirage is on the list because
# reaching for it instead of Io_of_flow would quietly pull conduit-mirage,
# tcpip and 46 other packages, and with them the assumption of a stack the
# confidential targets do not have.
FLOW_FORBIDDEN="unix threads lwt.unix cohttp-lwt-unix conduit-lwt-unix
mirage-flow-unix h2-lwt-unix h2-mirage tcpip conduit-mirage core_unix async"

status=0

fail() {
  echo "no_io_guard: FAIL $*" >&2
  status=1
}

# The package names inside a .opam depends: block, one per line. Filters out
# the build-only and test-only entries, which do not reach a unikernel.
declared_deps() {
  awk '
    /^depends: \[/ { inside = 1; next }
    inside && /^\]/  { inside = 0 }
    inside {
      if ($0 ~ /with-test|with-doc|with-dev-setup/) next
      if (match($0, /"[^"]+"/)) {
        name = substr($0, RSTART + 1, RLENGTH - 2)
        if (name != "ocaml" && name != "dune") print name
      }
    }
  ' "$1"
}

# Walks a package's declared dependencies, following the ones that live in
# this repository so a violation one level down is still found here.
check_package() {
  pkg="$1"
  shift
  forbidden="$*"
  file="$pkg.opam"
  [ -f "$file" ] || { fail "$file is missing -- run dune build @install"; return; }

  pending=$(declared_deps "$file")
  seen=""
  bad=""
  while [ -n "$pending" ]; do
    dep=$(printf '%s\n' "$pending" | head -n 1)
    pending=$(printf '%s\n' "$pending" | tail -n +2)
    case " $seen " in *" $dep "*) continue ;; esac
    seen="$seen $dep"

    for f in $forbidden; do
      [ "$dep" = "$f" ] && bad="$bad $dep"
    done

    if [ -f "$dep.opam" ]; then
      pending=$(printf '%s\n%s\n' "$pending" "$(declared_deps "$dep.opam")" | grep -v '^$' || true)
    fi
  done

  if [ -n "$bad" ]; then
    fail "$pkg depends on:$bad"
  else
    echo "  ok  $pkg"
  fi
}

echo "no_io_guard: declared dependencies (I/O, and zarith/GMP)"

for pkg in $OFFLINE; do
  check_package "$pkg" $FORBIDDEN
done

echo "no_io_guard: flow transports stay free of a host OS"

for pkg in $FLOW_TRANSPORTS; do
  check_package "$pkg" $FLOW_FORBIDDEN
done

# The check that does not rely on us having listed every hazard: link the
# offline closure into a Solo5-shaped executable that names no transport.
if [ -f validation/solo5/dune ]; then
  echo "no_io_guard: linking the offline closure with no transport"
  if "$DUNE" build validation/solo5/unikernel.exe 2>&1; then
    echo "  ok  validation/solo5/unikernel.exe"
  else
    fail "the offline closure no longer links without a transport"
  fi
else
  echo "no_io_guard: WARNING validation/solo5 is absent, link proof skipped" >&2
fi

# And the same question for the transport, which claims to reach a vsock: it
# must build and run over a flow that is not a socket, naming no Unix package.
# A transport that had smuggled in an assumption about file descriptors, DNS or
# a network stack would fail here rather than at deployment.
if [ -f validation/flow/dune ]; then
  echo "no_io_guard: driving the client over a non-socket flow"
  if "$DUNE" build validation/flow/flow_link.exe 2>&1; then
    echo "  ok  validation/flow/flow_link.exe"
  else
    fail "the client no longer works over an arbitrary flow"
  fi
else
  echo "no_io_guard: WARNING validation/flow is absent, flow link proof skipped" >&2
fi

# The same, for gRPC. Not written yet; the check is here so that adding it
# turns the warning off rather than needing this script edited.
if [ -f validation/grpc-flow/dune ]; then
  echo "no_io_guard: linking gRPC over a non-socket flow"
  if "$DUNE" build validation/grpc-flow/grpc_flow_link.exe 2>&1; then
    echo "  ok  validation/grpc-flow/grpc_flow_link.exe"
  else
    fail "gRPC no longer builds over an arbitrary flow"
  fi
else
  echo "no_io_guard: WARNING validation/grpc-flow is absent, gRPC link proof skipped" >&2
fi

if [ "$status" -eq 0 ]; then
  echo "no_io_guard: clean"
else
  echo "no_io_guard: violations found" >&2
fi
exit "$status"
