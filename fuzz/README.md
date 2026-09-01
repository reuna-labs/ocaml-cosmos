Crowbar targets for Bech32 addresses, protobuf transaction structures,
`SignDoc`, Amino JSON, CometBFT JSON-RPC and the submission state machine.

They run bounded under an ordinary compiler and as AFL targets under the
dedicated campaign switch. See `../docs/fuzzing.md` for properties, commands,
corpus retention and the distinction between CI maintenance and a sustained
campaign.

The seed corpus is deliberately small: Crowbar interprets each input for every
property registered by a target, and AFL grows target-specific corpora from it.
