@testable import DistrictLive
import Foundation
import XCTest

/// The protocol's constants and timing rules, as numbers.
final class TelemetryProtocolTests: XCTestCase {
    /// ⛔ THESE ARE THE SERVER'S NUMBERS, NOT TUNABLES. 4401 and 4403 are the
    /// broadcaster's close codes; the 90 s silence limit is three of its 30 s pings.
    func testTheProtocolConstants() {
        XCTAssertEqual(TelemetryProtocol.subprotocol, "distronode.telemetry.v1")
        XCTAssertEqual(TelemetryProtocol.tokenSubprotocolPrefix, "distronode.token.")
        XCTAssertEqual(TelemetryProtocol.closeUnauthorized, 4401)
        XCTAssertEqual(TelemetryProtocol.closeForbidden, 4403)
        XCTAssertEqual(TelemetryProtocol.renewalLeadMilliseconds, 60000)
        XCTAssertEqual(TelemetryProtocol.silenceLimitMilliseconds, 90000)
        XCTAssertEqual(TelemetryProtocol.connectTimeoutMilliseconds, 15000)
        XCTAssertEqual(TelemetryProtocol.stableAfterMilliseconds, 30000)
    }

    // MARK: - Backoff

    func testTheBackoffDoublesWithEachFailureBetweenHalfAndAllOfItsCeiling() {
        let ceilings: [Int64] = [2000, 4000, 8000, 16000, 32000, 60000, 60000]
        for (offset, ceiling) in ceilings.enumerated() {
            let failures = offset + 1
            XCTAssertEqual(TelemetryProtocol.backoffMilliseconds(failures: failures, jitter: 0), ceiling / 2)
            XCTAssertEqual(TelemetryProtocol.backoffMilliseconds(failures: failures, jitter: 1), ceiling)
        }
        XCTAssertEqual(TelemetryProtocol.backoffMilliseconds(failures: 1, jitter: 0.5), 1500)
    }

    /// ⛔ NEVER UNDER 1 s AND NEVER OVER 60 s, whatever the inputs.
    func testTheBackoffStaysWithinOneAndSixtySecondsForHostileInput() {
        for failures in [Int.min, -1, 0, 1, 2, 17, 1000, Int.max] {
            for jitter in [-5, 0, 0.3, 1, 7, .nan, .infinity, -.infinity] {
                let delay = TelemetryProtocol.backoffMilliseconds(failures: failures, jitter: jitter)
                XCTAssertGreaterThanOrEqual(delay, TelemetryProtocol.backoffFloorMilliseconds, "\(failures) \(jitter)")
                XCTAssertLessThanOrEqual(delay, TelemetryProtocol.backoffCapMilliseconds, "\(failures) \(jitter)")
            }
        }
        // A non-finite jitter is the middle of the range; an out-of-range one is clamped.
        XCTAssertEqual(TelemetryProtocol.backoffMilliseconds(failures: 1, jitter: .nan), 1500)
        XCTAssertEqual(TelemetryProtocol.backoffMilliseconds(failures: 1, jitter: -3), 1000)
        XCTAssertEqual(TelemetryProtocol.backoffMilliseconds(failures: 1, jitter: 3), 2000)
    }

    // MARK: - Renewal

    func testTheSocketIsReplacedAMinuteBeforeTheCredentialExpires() {
        let now: Int64 = 1_790_433_000_000
        XCTAssertEqual(TelemetryProtocol.renewalDelayMilliseconds(expiresAt: now + 900_000, now: now), 840_000)
    }

    func testTheRenewalIsFlooredAndCeilinged() {
        let now: Int64 = 1_790_433_000_000
        // Already inside the lead, or already expired: the floor, not a tight loop.
        XCTAssertEqual(TelemetryProtocol.renewalDelayMilliseconds(expiresAt: now + 30000, now: now), 5000)
        XCTAssertEqual(TelemetryProtocol.renewalDelayMilliseconds(expiresAt: now - 1_000_000, now: now), 5000)
        // A credential claiming a day: an hour at most.
        XCTAssertEqual(TelemetryProtocol.renewalDelayMilliseconds(expiresAt: now + 86_400_000, now: now), 3_600_000)
        // Arithmetic at the edges wraps rather than trapping, and stays in range.
        let extreme = TelemetryProtocol.renewalDelayMilliseconds(expiresAt: .max, now: .min)
        XCTAssertTrue((5000 ... 3_600_000).contains(extreme))
    }

    // MARK: - The credential and the offer

    func testOnlyCompactJWTCharactersArePresentable() {
        XCTAssertTrue(TelemetryProtocol.isPresentable("eyJhbGc.eyJzdWI-_.c2ln"))
        XCTAssertFalse(TelemetryProtocol.isPresentable(""))
        XCTAssertFalse(TelemetryProtocol.isPresentable("a b"))
        XCTAssertFalse(TelemetryProtocol.isPresentable("a,b"))
        XCTAssertFalse(TelemetryProtocol.isPresentable("a\r\nb"))
        XCTAssertFalse(TelemetryProtocol.isPresentable("tökén"))
        XCTAssertFalse(TelemetryProtocol.isPresentable("a=b"))
    }

    /// ⛔ THE VERSION FIRST, so a server that selects the first offer never echoes the
    /// credential back.
    func testTheVersionIsOfferedBeforeTheCredential() {
        XCTAssertEqual(
            TelemetryProtocol.offeredSubprotocols(token: "a.b.c"),
            ["distronode.telemetry.v1", "distronode.token.a.b.c"]
        )
    }

    // MARK: - The address

    func testTheWorkspaceIsAddedToTheQueryAndTheFragmentDropped() throws {
        let url = try TelemetryProtocol.socketURL(
            wsUrl: "wss://telemetry.example.com/ws/telemetry?region=eu#frag",
            workspaceId: "ws 1&x"
        ).get()

        XCTAssertEqual(url.absoluteString, "wss://telemetry.example.com/ws/telemetry?region=eu&workspaceId=ws%201%26x")
    }

    func testAPlainAddressIsTheWorkspaceAlone() throws {
        let url = try TelemetryProtocol.socketURL(wsUrl: "WSS://telemetry.example.com/ws", workspaceId: "ws_1").get()
        XCTAssertEqual(url.query, "workspaceId=ws_1")
    }

    func testAMissingAddressIsRefused() {
        XCTAssertEqual(TelemetryProtocol.socketURL(wsUrl: nil, workspaceId: "ws_1").failureOnly, .missing)
    }

    func testAnAddressThatIsNotAWebSocketURLIsRefused() {
        for raw in [
            "",
            "not a url",
            "https://telemetry.example.com/ws",
            "wss:///ws",
            "wss://",
            "ftp://h/x",
            "telemetry",
        ] {
            XCTAssertEqual(TelemetryProtocol.socketURL(wsUrl: raw, workspaceId: "ws_1").failureOnly, .invalid, raw)
        }
    }

    /// ⛔ PLAIN `ws` ONLY TO THIS MACHINE.
    func testPlainWsIsAcceptedOnlyForLoopback() {
        for raw in [
            "ws://localhost:8080/ws",
            "ws://LOCALHOST/ws",
            "ws://127.0.0.1:8080/ws",
            "ws://127.9.8.7/ws",
            "ws://[::1]:8080/ws",
        ] {
            XCTAssertNotNil(try? TelemetryProtocol.socketURL(wsUrl: raw, workspaceId: "ws_1").get(), raw)
        }
        for raw in [
            "ws://telemetry.example.com/ws",
            "ws://10.0.0.1/ws",
            "ws://127.0.0/ws",
            "ws://127.0.0.256/ws",
            "ws://128.0.0.1/ws",
            "ws://localhost.example.com/ws",
            "ws://[::2]/ws",
        ] {
            XCTAssertEqual(TelemetryProtocol.socketURL(wsUrl: raw, workspaceId: "ws_1").failureOnly, .insecure, raw)
        }
    }
}
