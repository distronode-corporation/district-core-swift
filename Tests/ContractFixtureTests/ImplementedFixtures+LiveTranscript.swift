import ContractGateSupport
import DistrictModel
import Foundation

// The live call transcript (`transcript` v1 on `/ws/telemetry`), in a file of its own because
// `ImplementedFixtures.swift` is at its 500-line ceiling.

extension ImplementedFixtures {
    /// ⛔ SIX SOCKET EVENTS AND THE TOKEN THAT OPENS THE SOCKET, gated from the commit that
    /// vendors them. The events go through the gate twice: as the five-key
    /// ``TelemetryEnvelope`` every socket event shares, and their `data` as the typed event
    /// ``TelemetryEnvelope/transcriptEvent`` reads it into, so a key the server sends and the
    /// model drops (or the reverse) fails here and not on a phone.
    ///
    /// ⚠️ `district-telemetry-token.json` IS THE DESKTOP FILE, BYTE FOR BYTE (the service
    /// writes one as a copy of the other), and is gated here against the same
    /// ``TelemetryTokenResponse`` `DesktopContractFixtureTests` uses there.
    ///
    /// ⚠️ THE SAME SIX EVENTS ARE IN `Tests/TranscriptFrames/`, where `TranscriptFrameTests`
    /// checks the contract's invariants on them, and that suite asserts the two copies are
    /// identical.
    static var liveTranscript: [ImplementedFixture] {
        [
            gate("district-telemetry-token.json", TelemetryTokenResponse.self),
            transcript("telemetry-event-transcript-ended.json", TranscriptEndedData.self),
            transcript("telemetry-event-transcript-error.json", TranscriptErrorData.self),
            transcript("telemetry-event-transcript-retracted.json", TranscriptRetractedData.self),
            transcript("telemetry-event-transcript-segment-interim.json", TranscriptSegmentData.self),
            transcript("telemetry-event-transcript-segment.json", TranscriptSegmentData.self),
            transcript("telemetry-event-transcript-snapshot.json", TranscriptSnapshotData.self),
        ]
    }

    /// The envelope through the gate, then its `data` as `type`, with the fixture's allowed
    /// `$.data` paths rebased to the root.
    private static func transcript(_ name: String, _ type: (some Codable).Type) -> ImplementedFixture {
        ImplementedFixture(name: name, type: "TelemetryEnvelope, \(type)") {
            let envelope = try StrictDecodeVerifier.verify(fixture: name, as: TelemetryEnvelope.self)
            let allowed = (StrictDecodeVerifier.allowedExplicitNulls[name] ?? []).map {
                "$" + $0.dropFirst("$.data".count)
            }
            _ = try StrictDecodeVerifier.verify(
                name: name,
                json: JSONEncoder().encode(envelope.data),
                as: type,
                allowingExplicitNulls: Set(allowed)
            )
        }
    }
}
