# A pure-Python secp256k1 + RFC 6979 + Cosmos address derivation, written to
# be an oracle for ocaml-cosmos. Independent of it in every respect.
import hashlib, hmac

P  = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
N  = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
Gx = 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
Gy = 0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8

def inv(a, m): return pow(a, m - 2, m)

def add(p, q):
    if p is None: return q
    if q is None: return p
    (x1, y1), (x2, y2) = p, q
    if x1 == x2 and (y1 + y2) % P == 0: return None
    if p == q: l = (3 * x1 * x1) * inv(2 * y1, P) % P
    else:      l = (y2 - y1) * inv(x2 - x1, P) % P
    x3 = (l * l - x1 - x2) % P
    return (x3, (l * (x1 - x3) - y1) % P)

def mul(k, p=(Gx, Gy)):
    r = None
    while k:
        if k & 1: r = add(r, p)
        p = add(p, p); k >>= 1
    return r

def compressed(pt):
    x, y = pt
    return bytes([2 + (y & 1)]) + x.to_bytes(32, "big")

def address(priv):
    pk = compressed(mul(priv))
    sha = hashlib.sha256(pk).digest()
    return hashlib.new("ripemd160", sha).digest()

def rfc6979_k(priv, digest):
    v = b"\x01" * 32
    k = b"\x00" * 32
    x = priv.to_bytes(32, "big")
    k = hmac.new(k, v + b"\x00" + x + digest, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    k = hmac.new(k, v + b"\x01" + x + digest, hashlib.sha256).digest()
    v = hmac.new(k, v, hashlib.sha256).digest()
    while True:
        v = hmac.new(k, v, hashlib.sha256).digest()
        cand = int.from_bytes(v, "big")
        if 1 <= cand < N: return cand
        k = hmac.new(k, v + b"\x00", hashlib.sha256).digest()
        v = hmac.new(k, v, hashlib.sha256).digest()

def sign(priv, digest):
    z = int.from_bytes(digest, "big")
    kk = rfc6979_k(priv, digest)
    R = mul(kk)
    r = R[0] % N
    s = inv(kk, N) * (z + r * priv) % N
    if s > N // 2: s = N - s          # low-S, as the SDK requires
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")

def bech32_polymod(values):
    GEN = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
    chk = 1
    for v in values:
        b = chk >> 25
        chk = (chk & 0x1ffffff) << 5 ^ v
        for i in range(5):
            chk ^= GEN[i] if ((b >> i) & 1) else 0
    return chk

def bech32_encode(hrp, data):
    CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    exp = [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp]
    chk = bech32_polymod(exp + data + [0, 0, 0, 0, 0, 0]) ^ 1
    return hrp + "1" + "".join(CHARSET[d] for d in data) + \
        "".join(CHARSET[(chk >> 5 * (5 - i)) & 31] for i in range(6))

def convertbits(data, frm, to, pad=True):
    acc = bits = 0; ret = []; maxv = (1 << to) - 1
    for value in data:
        acc = (acc << frm) | value; bits += frm
        while bits >= to:
            bits -= to; ret.append((acc >> bits) & maxv)
    if pad and bits: ret.append((acc << (to - bits)) & maxv)
    return ret

if __name__ == "__main__":
    # Sanity: the generator point's well-known compressed encoding.
    assert compressed(mul(1)).hex() == \
        "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
    keys = [1, 2, 3, 0xC0FFEE, N - 1,
            0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d]
    print("let key_vectors =")
    print("  [")
    for k in keys:
        pk = compressed(mul(k)).hex()
        ad = address(k)
        b32 = bech32_encode("cosmos", convertbits(list(ad), 8, 5))
        print('    ("%064x",' % k)
        print('      "%s",' % pk)
        print('      "%s",' % ad.hex())
        print('      "%s");' % b32)
    print("  ]")
    print()
    print("let signature_vectors =")
    print("  [")
    for k in keys[:4]:
        for msg in [b"", b"cosmos", b"the bytes that were signed"]:
            d = hashlib.sha256(msg).digest()
            print('    ("%064x", "%s", "%s");' % (k, d.hex(), sign(k, d).hex()))
    print("  ]")
