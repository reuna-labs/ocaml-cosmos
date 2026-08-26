#!/usr/bin/env python3
"""Cross-check CosmJS against the protoc and Go SDK fixtures.

Three implementations of the same transaction now exist: protoc (the reference
implementation of the wire format), the Go SDK (the reference implementation of
the protocol), and CosmJS (what the ecosystem's wallets actually run). They must
agree, and where they do not, the disagreement is the finding rather than
something to reconcile quietly.

CosmJS matters for a different reason from the other two. The SDK says what a
node will accept; CosmJS says what a user's wallet will sign. A library that
matched the specification and disagreed with CosmJS would be correct and
unusable.

usage: check.py   (from conformance/cosmjs)
"""
import json
import sys


def main():
    js = json.load(open("../fixtures/cosmjs.json"))
    sdk = json.load(open("../fixtures/sdk.json"))
    bad = 0

    for name, got in sorted(js["proto"].items()):
        for source, want in (
            ("protoc", read_hex("../fixtures/protoc/%s.hex" % name)),
            ("sdk", sdk["proto"].get(name)),
        ):
            if want is None:
                continue
            if want != got:
                print("  MISMATCH %s vs %s\n    %-6s %s\n    cosmjs %s"
                      % (name, source, source, want, got))
                bad += 1
            else:
                print("  cosmjs agrees with %-6s on %s" % (source, name))

    for name, got in sorted(js["amino"].items()):
        want = sdk["amino"].get(name)
        if want is None:
            continue
        if want != got:
            print("  MISMATCH amino/%s\n    sdk    %s\n    cosmjs %s" % (name, want, got))
            bad += 1
        else:
            print("  cosmjs agrees with sdk    on amino/%s" % name)

    sys.exit(1 if bad else 0)


def read_hex(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except FileNotFoundError:
        return None


if __name__ == "__main__":
    main()
