#!/usr/bin/env python3
"""Split the SDK oracle's output into files the OCaml test can read raw.

The amino half goes to one file per case, as bytes and nothing else. That
matters: the thing under test includes a JSON reader, and a test that used
that reader to load its own expected values would be checking it against
itself.

The protobuf half is checked against the protoc fixtures rather than written
out again -- two independent oracles agreeing is worth more than either alone,
and a disagreement between them is the finding.

usage: split.py   (from conformance/simd)
"""
import json
import os
import sys


def main():
    sdk = json.load(open("../fixtures/sdk.json"))

    os.makedirs("../fixtures/amino", exist_ok=True)
    for name, doc in sorted(sdk["amino"].items()):
        with open("../fixtures/amino/%s.json" % name, "w") as f:
            f.write(doc)
        print("  wrote fixtures/amino/%s.json (%d bytes)" % (name, len(doc)))

    bad = 0
    for name, got in sorted(sdk["proto"].items()):
        try:
            want = open("../fixtures/protoc/%s.hex" % name).read().strip()
        except FileNotFoundError:
            print("  (no protoc fixture for %s)" % name)
            continue
        if want != got:
            print("  MISMATCH %s\n    protoc %s\n    sdk    %s" % (name, want, got))
            bad += 1
        else:
            print("  agrees with protoc: %s" % name)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
