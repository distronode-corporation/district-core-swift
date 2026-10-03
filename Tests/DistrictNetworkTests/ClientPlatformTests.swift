import DistrictModel
@testable import DistrictNetwork
import Foundation
import XCTest

/// The platform the macOS app puts on the wire, at every site that carries one.
///
/// ⛔ THE iOS HALF IS PINNED BY THE EXISTING TESTS, UNCHANGED: every site defaults
/// to ``ClientPlatform/ios``, and `NativeAuthClientTests`, `AppleSignInExchangeTests`,
/// `RoomNameTests`, `EndpointTable` and the repository tests still assert the bytes
/// they asserted before the type existed. This file asserts the `macos` half, on
/// the bytes, site by site.
final class ClientPlatformTests: XCTestCase {
    private static let host = "https://auth.example.test"
    private static let tokenBody = """
    {"tokenType":"Bearer","accessToken":"at.jwt","accessTokenExpiresAt":1750000000000,\
    "refreshToken":"rt-opaque","refreshTokenExpiresAt":1755000000000}
    """

    func testTheWireValuesAreTheServersEnumMembers() {
        XCTAssertEqual(ClientPlatform.ios.wire, "ios")
        XCTAssertEqual(ClientPlatform.macos.wire, "macos")
        XCTAssertEqual(ClientPlatform.allCases.count, 2)
    }

    // ── native/token ─────────────────────────────────────────────────────────

    func testTheCodeExchangeDefaultsToIos() {
        let request = CodeExchangeRequest(
            code: "c",
            codeVerifier: "v",
            redirectUri: "r",
            deviceId: "d",
            deviceName: nil
        )
        XCTAssertEqual(request.clientPlatform, .ios)
    }

    func testTheMacCodeExchangeSendsMacos() async throws {
        let transport = TestTransport(json: Self.tokenBody)
        let request = CodeExchangeRequest(
            code: "one-time-code",
            codeVerifier: "verifier-43-chars",
            redirectUri: "districtai://auth",
            deviceId: "install-0123456789",
            deviceName: "Test Mac",
            clientPlatform: .macos
        )

        _ = try await TestNativeAuthClient(baseURL: XCTUnwrap(URL(string: Self.host)), transport: transport)
            .exchangeCode(request)

        let body = try XCTUnwrap(JSONWire.decode(transport.lastRequest?.body))
        XCTAssertEqual(body["platform"]?.stringValue, "macos")
        XCTAssertEqual(body["deviceName"]?.stringValue, "Test Mac")
    }

    // ── native/apple ─────────────────────────────────────────────────────────

    func testTheMacAppleExchangeSendsMacos() async throws {
        let transport = TestTransport(json: Self.tokenBody)
        let request = AppleNativeSignInRequest(
            identityToken: "header.payload.signature",
            nonce: "0011223344556677",
            deviceId: "install-0123456789",
            deviceName: nil,
            platform: .macos
        )
        XCTAssertEqual(request.platform, "macos")

        _ = try await TestNativeAuthClient(baseURL: XCTUnwrap(URL(string: Self.host)), transport: transport)
            .exchangeAppleIdentityToken(request)

        let body = try XCTUnwrap(JSONWire.decode(transport.lastRequest?.body))
        guard case let .object(fields) = body else { return XCTFail("the body is not a JSON object") }
        XCTAssertEqual(Set(fields.keys), ["platform", "identityToken", "nonce", "deviceId"])
        XCTAssertEqual(body["platform"]?.stringValue, "macos")
    }

    // ── devices/register ─────────────────────────────────────────────────────

    func testTheMacAlertRegisterSendsMacosAndNoKind() throws {
        let descriptor = DistrictEndpoints.registerPushToken(token: "apns-token", platform: .macos)
        XCTAssertEqual(try encoded(descriptor), #"{"platform":"macos","token":"apns-token"}"#)
        XCTAssertEqual(PushPlatform.macos, "macos")
    }

    /// ⛔ PRESENCE IS `kind: "desktop"` WITH `platform: "macos"`, the one pairing the
    /// server accepts for a desktop row from this package.
    func testTheMacPresenceRegisterIsTheDesktopPair() throws {
        let descriptor = DistrictEndpoints.registerPushToken(token: "install-nonce", kind: .desktop, platform: .macos)
        XCTAssertEqual(try encoded(descriptor), #"{"kind":"desktop","platform":"macos","token":"install-nonce"}"#)
    }

    func testEveryKindHasItsWireValue() {
        XCTAssertEqual(PushTokenKind.allCases.map(\.wire), [nil, "voip", "desktop"])
    }

    // ── calls/token ──────────────────────────────────────────────────────────

    func testTheMacRoomTokenIdentityIsMacos() throws {
        let room = try XCTUnwrap(RoomName(joining: "meet_standup"))
        let descriptor = DistrictEndpoints.roomToken(roomName: room, platform: .macos)
        XCTAssertEqual(try encoded(descriptor), #"{"identity":"macos","roomName":"meet_standup"}"#)
        XCTAssertEqual(RoomIdentity.value(for: .ios), RoomIdentity.value)
    }

    private func encoded(_ descriptor: ApiRequestDescriptor) throws -> String {
        guard case let .json(value) = descriptor.body else {
            XCTFail("not a JSON body")
            return ""
        }
        return try XCTUnwrap(String(data: JSONWire.encode(value), encoding: .utf8))
    }
}

/// `POST /api/district/telemetry/token`, through ``ApiClient/telemetryToken(workspaceId:)``.
final class TelemetryTokenClientTests: XCTestCase {
    private static let body = """
    {"success":true,"token":"a.b.c","expiresAt":1790433900000,"wsUrl":"wss://telemetry.example.com/ws/telemetry"}
    """

    func testItPostsTheWorkspaceInTheBodyAndDecodesTheGrant() async throws {
        let transport = TestTransport(json: Self.body)

        let result = await ApiClient.test(transport).telemetryToken(workspaceId: "ws_1")

        let grant = try XCTUnwrap(result.successOnly)
        XCTAssertEqual(grant.token, "a.b.c")
        XCTAssertEqual(grant.expiresAt, 1_790_433_900_000)
        XCTAssertEqual(grant.wsUrl, "wss://telemetry.example.com/ws/telemetry")
        XCTAssertEqual(transport.lastRequest?.method, .post)
        XCTAssertEqual(
            transport.lastRequest?.url.absoluteString,
            "https://www.distronode.com/api/district/telemetry/token"
        )
        XCTAssertEqual(
            transport.lastRequest?.body.flatMap { String(data: $0, encoding: .utf8) },
            #"{"workspaceId":"ws_1"}"#
        )
    }

    /// ⛔ A 200 THAT DOES NOT AFFIRM IS NOT A CREDENTIAL. A socket opened on it
    /// connects and is then closed with 4401.
    func testASuccessFalseBodyIsADecodingFailure() async {
        let transport = TestTransport(json: #"{"success":false,"token":"t","expiresAt":1,"wsUrl":null}"#)

        let result = await ApiClient.test(transport).telemetryToken(workspaceId: "ws_1")

        XCTAssertEqual(result.failureOnly, .decoding("TelemetryTokenResponse did not affirm success=true"))
    }

    func testARefusalIsTheNormalisedError() async {
        let transport = TestTransport(
            json: #"{"success":false,"error":"Access denied to workspace","code":"workspace_access_denied"}"#,
            status: 403
        )

        let result = await ApiClient.test(transport).telemetryToken(workspaceId: "ws_1")

        XCTAssertEqual(result.failureOnly?.httpStatus, 403)
    }
}
