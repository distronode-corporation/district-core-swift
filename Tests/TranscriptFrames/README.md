# Live transcript frames (hand-written, temporary)

These six files are **written by hand** from the examples in the service's `transcript` v1
wire contract (the revision with the §4.12 clarifications: a retraction carries `epoch`
beside `seq`, both null from the website; a subscribe is answered only once a first line
exists, so there is no empty opening snapshot; `transcript_error.op` echoes the op sent),
because the service's own fixtures for the five `transcript_*` events do not
exist yet. They stand in for them so the transcript models and the reducer can be tested
before the server side ships.

They are named exactly as the service will name its fixtures:

- `telemetry-event-transcript-segment.json`
- `telemetry-event-transcript-segment-interim.json`
- `telemetry-event-transcript-snapshot.json`
- `telemetry-event-transcript-ended.json`
- `telemetry-event-transcript-retracted.json`
- `telemetry-event-transcript-error.json`

**When the service's fixtures arrive,** copy them over these files, unchanged.
`TranscriptFrameTests` (in `Tests/ContractFixtureTests`) reads whatever is here and asserts
nothing that depends on the values written by hand, so it then checks the models against
the server's own output with no other edit. The same fixtures also arrive in
`contracts/mobile/` with the service's next contract sync, together with
`district-telemetry-token.json`; that sync moves `ContractFixtureTests`' count and decides
whether this directory is kept or deleted.

Nothing here is a contract fixture, and `contracts/` is not edited by hand (see
CONTRIBUTING.md).
