import Foundation

// The live transcript's allowlist entries, in a file of its own like `+Setup` and
// `+Meetings`. Chained into `allowedExplicitNulls` in `AllowedExplicitNulls+Union.swift`.

extension StrictDecodeVerifier {
    /// ⚠️ ONLY THE NULLS THESE FIXTURES CARRY, not every key the contract lets be null. The
    /// contract's full set (a segment's `language`, a snapshot's `epoch` and `lastSeq`, an
    /// error's `callId` and `op`, an end's `lastIndex`) is permission `TranscriptFrameTests`
    /// grants per frame; an entry here is permission for a null that is on disk.
    ///
    /// ⚠️ `telemetry-event-transcript-ended.json` and `district-telemetry-token.json` GET NO
    /// ENTRY: neither carries a null.
    static let liveTranscript: [String: Set<String>] = [
        // A caller line never repeats the caller's name (§4.5): `speakerName` is null on
        // every `caller` segment.
        "telemetry-event-transcript-segment.json": [
            "$.data.segment.speakerName",
        ],
        // The same caller turn while interim: no name, and `endedAt` is null until final.
        "telemetry-event-transcript-segment-interim.json": [
            "$.data.segment.speakerName",
            "$.data.segment.endedAt",
        ],
        // A live snapshot: `endedReason` is null whenever `live` is true (§4.12 Q9), and
        // segment 1 is the caller's.
        "telemetry-event-transcript-snapshot.json": [
            "$.data.endedReason",
            "$.data.segments[1].speakerName",
        ],
        // The website's retraction: `epoch` and `seq` are both null when the website sends
        // it, and set only when the agent does (§4.12 Q2).
        "telemetry-event-transcript-retracted.json": [
            "$.data.epoch",
            "$.data.seq",
        ],
        // `not_live` names no wait: `retryAfterMs` is set only on `rate_limited`.
        "telemetry-event-transcript-error.json": [
            "$.data.retryAfterMs",
        ],
    ]
}
