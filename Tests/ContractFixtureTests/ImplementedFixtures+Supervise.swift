import ContractGateSupport
import DistrictModel
import Foundation

// Live supervise (8.2.0), in a file of its own because `ImplementedFixtures.swift` is at its
// 500-line ceiling.

extension ImplementedFixtures {
    /// ⛔ FIVE FILES ARRIVED WITH THE WEBSITE'S SUPERVISE SYNC, each with the DTO and the
    /// repository that decodes it already in place, so ``ContractManifest/expectedFixtureCount``
    /// moves by five and none of them visits ``ContractManifest/unimplemented``.
    ///
    /// ⚠️ THE WHISPER LANDS ON THE SHARED ``SuccessResponse``: its 200 says nothing else.
    ///
    /// ⚠️ THE TWO RECEIPTS ARE A SOCKET EVENT WITH NO CODABLE `data` TYPE.
    /// ``TelemetryEnvelope/whisperReceipt`` reads them leniently, as the website does, so they
    /// go through the gate as the five-key ``TelemetryEnvelope`` and then their `data` is held
    /// to the three keys the receipt reads: a key the agent adds fails here, not on a phone.
    static var supervise: [ImplementedFixture] {
        [
            gate("district-call-monitor-token.json", CallMonitorResponse.self),
            gate("district-call-takeover.json", CallTakeoverResponse.self),
            gate("district-call-whisper.json", SuccessResponse.self),
            receipt("telemetry-event-whisper-applied.json"),
            receipt("telemetry-event-whisper-not-applied.json"),
        ]
    }

    /// The keys a `whisper_applied` event's `data` may carry: what
    /// ``TelemetryEnvelope/whisperReceipt`` reads.
    private static let receiptKeys: Set<String> = ["applied", "firstWords", "reason"]

    /// The envelope through the gate, then its `data` as a receipt this client reads whole:
    /// only the receipt's keys, a boolean `applied`, and a reason it knows by name.
    private static func receipt(_ name: String) -> ImplementedFixture {
        ImplementedFixture(name: name, type: "TelemetryEnvelope, WhisperReceipt") {
            let envelope = try StrictDecodeVerifier.verify(fixture: name, as: TelemetryEnvelope.self)
            let keys = Set(envelope.data.objectValue?.keys.map(\.self) ?? [])
            let dropped = keys.subtracting(receiptKeys)
            if !dropped.isEmpty {
                throw ContractGateFailure.droppedKeys(
                    fixture: name, type: "WhisperReceipt", path: "$.data", keys: dropped.sorted()
                )
            }
            guard let receipt = envelope.whisperReceipt else {
                throw ContractGateFailure.decodeFailed(
                    fixture: name, type: "WhisperReceipt", reason: "not a whisper_applied event with a boolean applied"
                )
            }
            if case let .unknown(wire)? = receipt.reason {
                throw ContractGateFailure.decodeFailed(
                    fixture: name, type: "WhisperReceipt", reason: "reason \(wire) is not one this client names"
                )
            }
        }
    }
}
