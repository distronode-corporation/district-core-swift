@testable import DistrictModel
import Foundation
import XCTest

/// The telemetry credential and the socket's envelope. The fixture-by-fixture
/// strict gate is `DesktopContractFixtureTests`; this file pins the behaviour no
/// fixture shows: the redaction, the unknown event type, the null address, and the
/// typed reads over the opaque `data`.
final class TelemetryResponsesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func encodeSorted(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try XCTUnwrap(String(data: encoder.encode(value), encoding: .utf8))
    }

    // MARK: - The credential

    /// ⚠️ `null` IS THE LOCAL-DEVELOPMENT ANSWER AND MUST ROUND-TRIP AS `null`, not as
    /// an absent key: synthesised `Encodable` would drop it.
    func testANullAddressDecodesAndReencodesAsNull() throws {
        let token = try decode(TelemetryTokenResponse.self, #"{"success":true,"token":"t","expiresAt":0,"wsUrl":null}"#)

        XCTAssertNil(token.wsUrl)
        XCTAssertEqual(try encodeSorted(token), #"{"expiresAt":0,"success":true,"token":"t","wsUrl":null}"#)
    }

    func testAMissingTokenIsADecodeFailure() {
        XCTAssertThrowsError(try decode(TelemetryTokenResponse.self, #"{"success":true,"expiresAt":0,"wsUrl":null}"#))
    }

    /// ⛔ THE CREDENTIAL NEVER REACHES A STRING: not through `description`, not through
    /// `debugDescription`, not through the mirror `dump` and XCTest walk.
    func testTheTokenIsRedactedEverywhereItCouldBePrinted() {
        let token = TelemetryTokenResponse(
            success: true,
            token: "secret.jwt.value",
            expiresAt: 1_790_433_900_000,
            wsUrl: "wss://telemetry.example.com/ws/telemetry"
        )
        var dumped = ""
        dump(token, to: &dumped)

        for shown in [String(describing: token), String(reflecting: token), "\(token)", dumped] {
            XCTAssertFalse(shown.contains("secret"), shown)
            XCTAssertTrue(shown.contains("<redacted>"), shown)
            XCTAssertTrue(shown.contains("1790433900000"), shown)
        }
        XCTAssertTrue(String(describing: token).contains("wss://telemetry.example.com"))
        let local = TelemetryTokenResponse(success: true, token: "t", expiresAt: 0, wsUrl: nil)
        XCTAssertTrue(String(describing: local).contains("wsUrl: nil"))
    }

    // MARK: - The event type

    func testEveryKnownEventTypeRoundTripsByName() throws {
        let names = [
            "call_started", "call_updated", "call_ended", "call_ringing", "tool_outcome", "message_received",
            "message_sent",
        ]
        XCTAssertEqual(TelemetryEventType.known.map(\.wire), names)
        for name in names {
            let decoded = try decode(TelemetryEventType.self, "\"\(name)\"")
            XCTAssertNotEqual(decoded, .unknown(name))
            XCTAssertEqual(try encodeSorted(decoded), "\"\(name)\"")
        }
    }

    /// ⚠️ A NAME THIS CLIENT DOES NOT KNOW KEEPS ITS NAME rather than failing the
    /// envelope; the server adds event types over time.
    func testAnUnknownEventTypeIsKeptAndReencodedAsSent() throws {
        let decoded = try decode(TelemetryEventType.self, #""call_parked""#)

        XCTAssertEqual(decoded, .unknown("call_parked"))
        XCTAssertEqual(decoded.wire, "call_parked")
        XCTAssertEqual(try encodeSorted(decoded), #""call_parked""#)
    }

    func testANonStringEventTypeIsADecodeFailure() {
        XCTAssertThrowsError(try decode(TelemetryEventType.self, "42"))
    }

    // MARK: - The envelope

    func testTheRingingUserIdsAreTheStringElementsOnly() throws {
        let envelope = try decode(TelemetryEnvelope.self, """
        {"workspaceId":"ws_1","callId":"call_1","eventType":"call_ringing",
         "data":{"callId":"call_1","userIds":["user_1",7,null,"user_2"]},"timestamp":"t"}
        """)

        XCTAssertEqual(envelope.eventType, .callRinging)
        XCTAssertEqual(envelope.ringingUserIds, ["user_1", "user_2"])
        XCTAssertNil(envelope.callStatus)
    }

    func testTheReadsAnswerNilForAShapeWithoutTheirKey() throws {
        let envelope = try decode(TelemetryEnvelope.self, """
        {"workspaceId":"ws_1","callId":"call_1","eventType":"call_updated",
         "data":{"status":7,"userIds":"user_1"},"timestamp":"t"}
        """)
        let scalar = try decode(TelemetryEnvelope.self, """
        {"workspaceId":"ws_1","callId":"call_1","eventType":"tool_outcome","data":"text","timestamp":"t"}
        """)

        XCTAssertNil(envelope.callStatus)
        XCTAssertNil(envelope.ringingUserIds)
        XCTAssertNil(scalar.callStatus)
        XCTAssertNil(scalar.ringingUserIds)
    }

    func testTheCallStatusIsRead() {
        let envelope = TelemetryEnvelope(
            workspaceId: "ws_1",
            callId: "call_1",
            eventType: .callUpdated,
            data: .object(["status": .string("completed")]),
            timestamp: "t"
        )
        XCTAssertEqual(envelope.callStatus, "completed")
    }

    /// ⛔ A CALL ROW IS CUSTOMER DATA: the caller's number never reaches a string.
    func testTheDataIsLeftOutOfEverythingPrintable() {
        let envelope = TelemetryEnvelope(
            workspaceId: "ws_1",
            callId: "call_1",
            eventType: .unknown("later"),
            data: .object(["from": .string("+14165550142")]),
            timestamp: "2026-09-26T14:30:00.000Z"
        )
        var dumped = ""
        dump(envelope, to: &dumped)

        for shown in [String(describing: envelope), dumped] {
            XCTAssertFalse(shown.contains("555"), shown)
            XCTAssertTrue(shown.contains("<omitted>"), shown)
            XCTAssertTrue(shown.contains("later"), shown)
            XCTAssertTrue(shown.contains("ws_1"), shown)
        }
    }
}
