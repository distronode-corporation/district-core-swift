@testable import DistrictLive
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// `ApiClient`'s two conformances, on the bytes.
final class LiveAPITests: XCTestCase {
    /// ⛔ THE DESKTOP PAIR: `kind: "desktop"` with `platform: "macos"`, the only pairing
    /// the server accepts for a presence row from this package.
    func testPresenceRegistersTheDesktopPair() async {
        let transport = LiveHTTPTransport(json: #"{"success":true}"#)

        let result = await ApiClient.live(transport).registerPresence(token: "install-nonce-1")

        XCTAssertNotNil(try? result.get())
        XCTAssertEqual(
            transport.requests.first?.url.absoluteString,
            "https://www.distronode.com/api/district/devices/register"
        )
        XCTAssertEqual(transport.bodies, [#"{"kind":"desktop","platform":"macos","token":"install-nonce-1"}"#])
    }

    func testPresenceUnregistersWithTheEmptyBody() async {
        let transport = LiveHTTPTransport(json: #"{"success":true}"#)

        let result = await ApiClient.live(transport).unregisterPresence()

        XCTAssertNotNil(try? result.get())
        XCTAssertEqual(
            transport.requests.first?.url.absoluteString,
            "https://www.distronode.com/api/district/devices/unregister"
        )
        XCTAssertEqual(transport.bodies, ["{}"])
    }

    func testABodyThatDoesNotAffirmIsAFailure() async {
        let transport = LiveHTTPTransport(json: #"{"success":false}"#, #"{"success":false}"#)
        let client = ApiClient.live(transport)

        let registered = await client.registerPresence(token: "n")
        let unregistered = await client.unregisterPresence()

        XCTAssertEqual(registered.failureOnly, .decoding("PresenceRegisterResponse did not affirm success=true"))
        XCTAssertEqual(unregistered.failureOnly, .decoding("PresenceUnregisterResponse did not affirm success=true"))
    }

    func testTheMinterIsTheTelemetryTokenRoute() async throws {
        let transport = LiveHTTPTransport(
            json: #"{"success":true,"token":"a.b.c","expiresAt":1790433900000,"wsUrl":"wss://telemetry.example.com/ws/telemetry"}"#
        )

        let grant = try await ApiClient.live(transport).mintTelemetryToken(workspaceId: "ws_1").get()

        XCTAssertEqual(grant.token, "a.b.c")
        XCTAssertEqual(
            transport.requests.first?.url.absoluteString,
            "https://www.distronode.com/api/district/telemetry/token"
        )
        XCTAssertEqual(transport.bodies, [#"{"workspaceId":"ws_1"}"#])
    }
}
