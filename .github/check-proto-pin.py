#!/usr/bin/env python3
"""Every vendored .proto must match the sha256 recorded in docs/protocol-pin.md.

The pin document is only worth having if it describes the tree that is actually
there. This is what keeps the two from drifting apart quietly -- a schema
updated without the table, or a table edited without the schema, both fail here.

usage: python3 .github/check-proto-pin.py   (from the repository root)
"""
import hashlib
import io
import os
import re
import sys


def main():
    doc = io.open("docs/protocol-pin.md", encoding="utf-8").read()
    recorded = dict(
        re.findall(r"^\| `([^`]+\.proto)` \| `([0-9a-f]{64})` \|$", doc, re.M)
    )
    if not recorded:
        print("no sha256 table found in docs/protocol-pin.md")
        return 1

    bad = 0
    seen = set()
    for root, _, names in os.walk("proto"):
        for n in sorted(names):
            if not n.endswith(".proto"):
                continue
            path = os.path.join(root, n)
            rel = os.path.relpath(path, "proto")
            seen.add(rel)
            got = hashlib.sha256(io.open(path, "rb").read()).hexdigest()
            if recorded.get(rel) != got:
                print("MISMATCH          %s" % rel)
                bad += 1

    for rel in sorted(set(recorded) - seen):
        print("RECORDED, ABSENT  %s" % rel)
        bad += 1

    print("%d recorded, %d on disk, %d wrong" % (len(recorded), len(seen), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
