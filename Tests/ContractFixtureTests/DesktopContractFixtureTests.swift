import ContractGateSupport
import DistrictModel
@testable import DistrictNetwork
import Foundation
import XCTest

/// The desktop half of the contract gate: every file in `contracts/desktop/`,
/// through the DTO the macOS app decodes it with.
///
/// ⛔ AN EXACT COUNT AND AN EXPLICIT MAP, the mobile suite's two guards. A file the
/// server adds is a red test here until somebody decides what decodes it, and a path
/// that resolved to the wrong directory is red rather than a pass over nothing.
///
/// ⚠️ TWELVE GO THROUGH THE STRICT GATE (no unlisted null, decode, re-encode, equal
/// key sets at every level). The thirteenth, the scheduling hand-off, has no Codable
/// DTO by design: `SchedulingHandoffClient` decodes it by hand and refuses a missing
/// or an extra key itself, so it is run through exactly that decoder.
final class DesktopContractFixtureTests: XCTestCase {
    static let expectedFixtureCount = 13

    /// Each fixture and what verifies it.
    private static let verifiers: [String: @Sendable () throws -> Void] = [
        "district-call-hangup.json": { try gate("district-call-hangup.json", as: CallHangUpResponse.self) },
        "district-device-register-desktop.json": {
            try gate("district-device-register-desktop.json", as: SuccessResponse.self)
        },
        "district-scheduling-handoff.json": { try handoff() },
        "district-telemetry-token.json": { try gate("district-telemetry-token.json", as: TelemetryTokenResponse.self) },
        "telemetry-event-call-ended-row.json": { try envelope("telemetry-event-call-ended-row.json") },
        "telemetry-event-call-ended.json": { try envelope("telemetry-event-call-ended.json") },
        "telemetry-event-call-ringing.json": { try envelope("telemetry-event-call-ringing.json") },
        "telemetry-event-call-started-sinch.json": { try envelope("telemetry-event-call-started-sinch.json") },
        "telemetry-event-call-started.json": { try envelope("telemetry-event-call-started.json") },
        "telemetry-event-call-updated.json": { try envelope("telemetry-event-call-updated.json") },
        "telemetry-event-message-received.json": { try envelope("telemetry-event-message-received.json") },
        "telemetry-event-message-sent.json": { try envelope("telemetry-event-message-sent.json") },
        "telemetry-event-tool-outcome.json": { try envelope("telemetry-event-tool-outcome.json") },
    ]

    @discardableResult
    private static func gate<T: Codable>(_ name: String, as type: T.Type) throws -> T {
        try StrictDecodeVerifier.verify(
            name: name,
            json: DesktopContractFixtures.read(name),
            as: type,
            allowingExplicitNulls: DesktopAllowedNulls.byFixture[name] ?? []
        )
    }

    @discardableResult
    private static func envelope(_ name: String) throws -> TelemetryEnvelope {
        try gate(name, as: TelemetryEnvelope.self)
    }

    @discardableResult
    private static func handoff() throws -> SchedulingHandoff {
        try SchedulingHandoffClient.decode(DesktopContractFixtures.read("district-scheduling-handoff.json")).get()
    }

    // MARK: - The guards

    func testTheDesktopDirectoryIsPopulatedWithExactlyThirteenFixtures() throws {
        let names = try DesktopContractFixtures.allFixtureNames()
        XCTAssertEqual(
            names.count,
            Self.expectedFixtureCount,
            """
            desktop fixture count changed: \(names.count) on disk, \(Self.expectedFixtureCount) expected.
              A file the server added needs a verifier below in the same commit; a stale
              or partial checkout is fixed, not matched. On disk: \(names.joined(separator: ", "))
            """
        )
    }

    func testEveryDesktopFixtureHasExactlyOneVerifier() throws {
        let onDisk = try Set(DesktopContractFixtures.allFixtureNames())
        XCTAssertEqual(Set(Self.verifiers.keys), onDisk)
    }

    func testEveryDesktopFixturePassesItsVerifier() throws {
        for name in try DesktopContractFixtures.allFixtureNames() {
            let verify = try XCTUnwrap(Self.verifiers[name], "\(name) has no verifier")
            XCTAssertNoThrow(try verify(), name)
        }
    }

    func testTheNullRegisterIsTheReviewedSize() throws {
        let total = DesktopAllowedNulls.byFixture.values.map(\.count).reduce(0, +)
        XCTAssertEqual(total, DesktopAllowedNulls.expectedCount)
        let onDisk = try Set(DesktopContractFixtures.allFixtureNames())
        XCTAssertTrue(Set(DesktopAllowedNulls.byFixture.keys).isSubset(of: onDisk))
    }

    // MARK: - The values each fixture exists to pin

    func testTheTelemetryCredential() throws {
        let token = try Self.gate("district-telemetry-token.json", as: TelemetryTokenResponse.self)
        XCTAssertTrue(token.success)
        XCTAssertEqual(token.token, "contract-telemetry-token")
        XCTAssertEqual(token.expiresAt, 1_790_433_900_000)
        XCTAssertEqual(token.wsUrl, "wss://telemetry.example.com/ws/telemetry")
    }

    /// ⛔ THE RING NAMES USERS BY ID, and a desktop rings only when its own `sub` is
    /// in the list.
    func testTheRingingEventCarriesIdsOnly() throws {
        let ringing = try Self.envelope("telemetry-event-call-ringing.json")
        XCTAssertEqual(ringing.eventType, .callRinging)
        XCTAssertEqual(ringing.workspaceId, "ws_desktop_contract")
        XCTAssertEqual(ringing.callId, "call_desktop_contract")
        XCTAssertEqual(ringing.ringingUserIds, ["user_desktop_contract"])
        XCTAssertEqual(ringing.data.objectValue.map { Set($0.keys) }, ["callId", "userIds"])
    }

    func testEveryCallEventShapeCarriesItsStatus() throws {
        XCTAssertEqual(try Self.envelope("telemetry-event-call-updated.json").callStatus, "ringing")
        XCTAssertEqual(try Self.envelope("telemetry-event-call-started.json").callStatus, "in-progress")
        XCTAssertEqual(try Self.envelope("telemetry-event-call-started-sinch.json").callStatus, "in-progress")
        XCTAssertEqual(try Self.envelope("telemetry-event-call-ended.json").callStatus, "completed")
        XCTAssertEqual(try Self.envelope("telemetry-event-call-ended-row.json").callStatus, "completed")
    }

    func testEveryEventTypeIsOneThisClientKnows() throws {
        let types = try Self.verifiers.keys.filter { $0.hasPrefix("telemetry-event-") }
            .map { try Self.envelope($0).eventType }
        XCTAssertFalse(types.contains {
            if case .unknown = $0 {
                true
            } else {
                false
            }
        })
        // ⚠️ THE SEVEN WORKSPACE EVENTS. The five `transcript_*` events are subscribed to,
        // not relayed, and their frames are checked by `TranscriptFrameTests`.
        XCTAssertEqual(Set(types), Set(TelemetryEventType.known.filter { !$0.isTranscript }))
    }

    /// ⚠️ FOR A MESSAGE EVENT THE ENVELOPE'S `callId` IS THE MESSAGE ID.
    func testAMessageEventsCallIdIsTheMessageId() throws {
        let received = try Self.envelope("telemetry-event-message-received.json")
        XCTAssertEqual(received.callId, received.data["messageId"]?.stringValue)
    }

    func testTheHangUpAndTheRegister() throws {
        let hangUp = try Self.gate("district-call-hangup.json", as: CallHangUpResponse.self)
        XCTAssertTrue(hangUp.success)
        XCTAssertTrue(hangUp.ended)
        XCTAssertTrue(try Self.gate("district-device-register-desktop.json", as: SuccessResponse.self).success)
    }

    func testTheHandOffDecodesThroughTheClientsOwnDecoder() throws {
        let handoff = try Self.handoff()
        XCTAssertEqual(handoff.url.host, "www.distronode.com")
        XCTAssertEqual(handoff.expiresIn, 60)
    }

    /// ⛔ THE GATE CAN FAIL ON THIS DTO. A top-level key the envelope does not model
    /// vanishes on re-encode, and the comparison catches it.
    func testAnUnmodelledEnvelopeKeyIsCaught() throws {
        let body = #"{"workspaceId":"w","callId":"c","eventType":"call_ended","data":{},"timestamp":"t","extra":1}"#
        XCTAssertThrowsError(
            try StrictDecodeVerifier.verify(name: "probe", json: Data(body.utf8), as: TelemetryEnvelope.self)
        )
    }
}
