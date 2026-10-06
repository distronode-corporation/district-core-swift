import Foundation

// The live transcript's half of the manifest, in a file of its own for the same
// `file_length` reason as `ContractManifest+Setup.swift`.

extension ContractManifest {
    /// Five of the six `transcript_*` fixtures carry a null, gated in
    /// `ImplementedFixtures+LiveTranscript.swift`.
    ///
    /// ⚠️ EIGHT paths, each named with its reason in `AllowedExplicitNulls+LiveTranscript.swift`.
    /// `telemetry-event-transcript-ended.json` and `district-telemetry-token.json` carry none.
    static let liveTranscriptFixturesWithAllowedNulls: Set<String> = [
        "telemetry-event-transcript-error.json",
        "telemetry-event-transcript-retracted.json",
        "telemetry-event-transcript-segment-interim.json",
        "telemetry-event-transcript-segment.json",
        "telemetry-event-transcript-snapshot.json",
    ]
}
