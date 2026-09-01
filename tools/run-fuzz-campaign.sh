#!/bin/sh

set -eu

switch=${COSMOS_AFL_SWITCH:-}
seconds=${FUZZ_SECONDS:-3600}
build_dir=${FUZZ_BUILD_DIR:-_build-afl}
output_root=${FUZZ_OUTPUT_ROOT:-fuzz-results}
target=${1:-}
targets="fuzz_bech32 fuzz_proto fuzz_sign_doc fuzz_amino fuzz_json fuzz_submission"

case "$seconds" in
  ''|*[!0-9]*)
    echo "FUZZ_SECONDS must be a positive integer" >&2
    exit 2
    ;;
  0)
    echo "FUZZ_SECONDS must be greater than zero" >&2
    exit 2
    ;;
esac

if ! command -v afl-fuzz >/dev/null 2>&1; then
  echo "afl-fuzz is required" >&2
  exit 2
fi

if [ -z "$switch" ]; then
  switch=$(opam switch show 2>/dev/null) || {
    echo "no current opam switch; set COSMOS_AFL_SWITCH" >&2
    exit 2
  }
elif ! opam switch show --switch "$switch" >/dev/null 2>&1; then
    echo "opam switch '$switch' does not exist" >&2
    exit 2
fi

if [ -n "$target" ]; then
  case " $targets " in
    *" $target "*) targets=$target ;;
    *)
      echo "unknown target: $target" >&2
      echo "expected one of: $targets" >&2
      exit 2
      ;;
  esac
fi

opam exec --switch "$switch" -- \
  dune build --build-dir "$build_dir" fuzz/

mkdir -p "$output_root"

for name in $targets; do
  executable="$build_dir/default/fuzz/$name.exe"
  output="$output_root/$name"
  echo "Running $name for $seconds seconds; evidence: $output"
  AFL_NO_UI=1 afl-fuzz \
    -V "$seconds" \
    -i fuzz/corpus/common \
    -o "$output" \
    -- "$executable" @@
done
