# Live transcript frames (the service's fixtures)

These six files are the service's own fixtures for the five `transcript_*` events of the
`transcript` v1 wire contract, copied byte for byte from its `contracts/mobile/` set
(service commit `909936271`). They follow the contract revision with the §4.12
clarifications (Q1 to Q17): a retraction carries `epoch` beside `seq`, both null from the
website; a subscribe is answered only once a first line exists, so there is no empty
opening snapshot; a snapshot carries `endedReason`, null while live; `transcript_error.op`
echoes the op sent.

- `telemetry-event-transcript-segment.json`
- `telemetry-event-transcript-segment-interim.json`
- `telemetry-event-transcript-snapshot.json`
- `telemetry-event-transcript-ended.json`
- `telemetry-event-transcript-retracted.json`
- `telemetry-event-transcript-error.json`

`TranscriptFrameTests` (in `Tests/ContractFixtureTests`) reads whatever is here and asserts
only what holds for any frame the contract allows, so a regenerated set is a file copy
with no other edit. If one fails to decode, the models and the contract disagree: report
it, never edit the file.

The same files (with `district-telemetry-token.json`) reach `contracts/mobile/` with this
package's next contract sync; that sync moves `ContractFixtureTests`' count and decides
whether this directory is kept or deleted. Until then this copy is what the transcript
models are tested against.

Nothing here is edited by hand, like `contracts/` (see CONTRIBUTING.md).
