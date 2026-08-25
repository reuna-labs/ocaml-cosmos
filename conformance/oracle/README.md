# The secp256k1 oracle

`secp256k1.py` is a complete, independent implementation of everything
`cosmos-crypto` does: point multiplication over secp256k1, SEC 1 compression,
RFC 6979 nonce derivation, ECDSA with low-S normalisation,
`RIPEMD160(SHA256(pubkey))`, and bech32. It shares no code with this
repository, and it exists so that the vectors in `test/test_crypto.ml` are
evidence about the protocol rather than a record of this library agreeing with
itself.

It is Python because the point is independence, not speed. Two hundred lines of
schoolbook elliptic curve arithmetic are slow and obviously correct; the value
is that nothing in it came from `lib/`.

## Regenerating the vectors

```sh
python3 conformance/oracle/secp256k1.py
```

The output is the two `let` bindings at the top of `test/test_crypto.ml`.
Paste them in and run `dune runtest`. Nothing should change.

## The check that does not depend on this file at all

Private key `1` derives hash160
`751e76e8199196d454941c45d1b3a323f1433bd6`. That is the witness program in
[BIP-173's own SegWit example](https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki),
`bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4`, published years before any of
this. The Cosmos spelling in the vectors has the same bech32 data part —
`w508d6qejxtdg4y5r3zarvary0c5xw7k` — and a different checksum, because the
checksum covers the human-readable part.

If the point multiplication, the compression, either hash, or the bit
conversion were wrong, that would not line up. It is the one vector here whose
provenance predates both implementations.

## What this oracle is not

It is not the SDK. Agreeing with it establishes that the cryptography is
right; it says nothing about whether a `SignDoc` was assembled correctly, which
is what the CosmJS and `simd` oracles in the sibling directories are for. See
`../README.md`.
