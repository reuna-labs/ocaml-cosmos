#!/usr/bin/env python3
"""Fill @@name@@ placeholders in a .txtpb.in from already-generated .hex files.

A composite message embeds another message's encoding as a bytes field.
Writing those bytes by hand would make the .txtpb unreviewable, so the
templates carry placeholders and this substitutes them.

protoc's own Any expansion -- [type.googleapis.com/cosmos.bank.v1beta1.MsgSend]
-- is deliberately not used. It writes that host into type_url, and Cosmos
uses the leading-slash form (/cosmos.bank.v1beta1.MsgSend), so the bytes would
be wrong in a way that is easy to miss.

usage: expand.py <name> <fixtures-dir>
"""
import re
import sys


def escape(hexstr):
    """Bytes as a protobuf text-format string literal."""
    out = []
    for c in bytes.fromhex(hexstr.strip()):
        if c == 0x22:  # "
            out.append('\\"')
        elif c == 0x5C:  # backslash
            out.append("\\\\")
        elif 0x20 <= c < 0x7F:
            out.append(chr(c))
        else:
            out.append("\\%03o" % c)
    return "".join(out)


def main():
    name, fixtures = sys.argv[1], sys.argv[2]
    src = open("conformance/protoc/%s.txtpb.in" % name).read()

    def sub(m):
        with open("%s/%s.hex" % (fixtures, m.group(1))) as f:
            return escape(f.read())

    with open("conformance/protoc/%s.txtpb" % name, "w") as f:
        f.write(re.sub(r"@@([a-z0-9_]+)@@", sub, src))


if __name__ == "__main__":
    main()
