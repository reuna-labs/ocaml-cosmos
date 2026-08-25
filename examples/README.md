The guarded live-network executable belongs here, in `cosmos-rpc-unix` — it is
the only thing in this repository that signs with a real key and touches a
network. Empty until G10 L3. It must refuse to run without an explicitly
supplied testnet chain id, key and destination, the way
`ocaml-tron/examples/nile_transfer.ml` does.
