import ContractGateSupport
import DistrictModel
@testable import DistrictNetwork
import Foundation
import XCTest

/// The second factor after Sign in with Apple: the Apple route's `401 mfa_required`,
/// and `POST /api/auth/native/mfa`.
///
/// ⛔ THE TWO BODIES THAT MATTER ARE THE SERVICE'S OWN RECORDINGS. The 401 that opens the
/// code step and the grant that closes it are read from `contracts/mobile/`, the bytes
/// the server's suite pins, so a renamed key fails here rather than on a phone.
final class NativeMfaClientTests: XCTestCase {
    private struct Row {
        let status: Int
        let body: String
        let expected: NativeMfaResult<MirrorTokens>
        let line: UInt

        init(_ status: Int, _ body: String, _ expected: NativeMfaResult<MirrorTokens>, line: UInt = #line) {
            self.status = status
            self.body = body
            self.expected = expected
            self.line = line
        }
    }

    private enum Fixture {
        static let host = "https://auth.example.test"

        /// What `district-native-apple-mfa-required.json` carries.
        static let ticket = "q6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s"
        static let expiresAt = Date(timeIntervalSince1970: 1_786_804_500) // 2026-08-15T14:35:00Z

        /// What `district-native-mfa.json` carries, without `tokenType`.
        static let grant = MirrorTokens(
            accessToken: "access-contract-token",
            accessTokenExpiresAt: 1_786_804_800_000,
            refreshToken: "refresh-contract-token",
            refreshTokenExpiresAt: 1_791_988_200_000
        )

        static let appleRequest = AppleNativeSignInRequest(
            identityToken: "header.payload.signature",
            nonce: "0011223344556677",
            deviceId: "install-0123456789",
            deviceName: "Test iPhone"
        )

        static let challenge = NativeMfaChallenge(ticket: ticket, expiresAt: expiresAt)

        static let mfaRequest = NativeMfaRequest(
            challenge: challenge,
            code: "123456",
            deviceId: "install-0123456789",
            deviceName: "Test iPhone"
        )

        static func recorded(_ name: String) throws -> String {
            try XCTUnwrap(String(bytes: ContractFixtures.read(name), encoding: .utf8))
        }
    }

    private func makeClient(_ transport: TestTransport) -> TestNativeAuthClient {
        TestNativeAuthClient(baseURL: URL(string: Fixture.host)!, transport: transport)
    }

    // ── The Apple route's 401 ────────────────────────────────────────────────

    /// ⛔ THE RECORDED 401 OPENS THE CODE STEP, carrying the ticket verbatim and the
    /// expiry parsed. Nothing is signed in: the result is not `.success`.
    func testTheRecordedMfaRequiredAnswerIsTheCodeStep() async throws {
        let body = try Fixture.recorded("district-native-apple-mfa-required.json")
        let client = makeClient(TestTransport(json: body, status: 401))

        let result = await client.exchangeAppleIdentityToken(Fixture.appleRequest)

        XCTAssertEqual(result, .mfaRequired(Fixture.challenge))
    }

    /// ⛔ ANY OTHER 401 STAYS AMBIGUOUS. A code sheet for a body that is not the
    /// route's `mfa_required`, or for a ticket that could never be redeemed, would ask
    /// for a code that cannot work.
    func testAnyOther401IsStillTransportFailure() async {
        let bodies = [
            "{}",
            "",
            "<html>unauthorized</html>",
            #"{"error":"invalid_credentials","code":"invalid_credentials","message":"x"}"#,
            mfaBody(error: "mfa_required", ticket: ""),
            mfaBody(error: "something_else", ticket: "t"),
            #"{"error":"mfa_required","code":"MFA_REQUIRED","message":"x"}"#,
        ]

        for body in bodies {
            let client = makeClient(TestTransport(json: body, status: 401))
            let result = await client.exchangeAppleIdentityToken(Fixture.appleRequest)
            XCTAssertEqual(result, .transportFailure, "body: \(body)")
        }
    }

    private func mfaBody(error: String, ticket: String) -> String {
        #"{"error":"\#(error)","code":"X","message":"x","mfaTicket":"\#(ticket)","#
            + #""mfaTicketExpiresAt":"2026-08-15T14:35:00.000Z"}"#
    }

    /// ⚠️ A 401 WITH NO BODY AT ALL takes the same ambiguous branch.
    func testA401WithNoBodyIsAmbiguous() async {
        let result = await makeClient(TestTransport(status: 401)).exchangeAppleIdentityToken(Fixture.appleRequest)

        XCTAssertEqual(result, .transportFailure)
    }

    /// ⛔ THE PKCE EXCHANGE NEVER OPENS THE CODE STEP, even handed the Apple route's body.
    /// The browser leg asks for the code on the web page before a code exists.
    func testThePkceExchangeNeverAnswersMfaRequired() async throws {
        let body = try Fixture.recorded("district-native-apple-mfa-required.json")
        let client = makeClient(TestTransport(json: body, status: 401))

        let result = await client.exchangeCode(CodeExchangeRequest(
            code: "c",
            codeVerifier: "v",
            redirectUri: "districtai://auth/callback",
            deviceId: "install-0123456789",
            deviceName: nil
        ))

        XCTAssertEqual(result, .transportFailure)
    }

    // ── The challenge ────────────────────────────────────────────────────────

    /// ⚠️ AN EXPIRY THIS BUILD CANNOT READ IS NOT AN EXPIRED TICKET. The server stays the
    /// judge; the local check only spares a request certain to fail.
    func testExpiry() {
        let challenge = Fixture.challenge
        XCTAssertFalse(challenge.isExpired(at: Fixture.expiresAt.addingTimeInterval(-1)))
        XCTAssertTrue(challenge.isExpired(at: Fixture.expiresAt))
        XCTAssertTrue(challenge.isExpired(at: Fixture.expiresAt.addingTimeInterval(60)))

        let unknown = NativeMfaChallenge(ticket: "t", expiresAt: nil)
        XCTAssertFalse(unknown.isExpired(at: .distantFuture))
    }

    func testAnUnreadableExpiryIsKeptAsUnknown() throws {
        let response = NativeMfaRequiredResponse(
            error: "mfa_required",
            code: "MFA_REQUIRED",
            message: "m",
            mfaTicket: "ticket",
            mfaTicketExpiresAt: "soon"
        )

        let challenge = try XCTUnwrap(NativeMfaChallenge(response))

        XCTAssertEqual(challenge.ticket, "ticket")
        XCTAssertNil(challenge.expiresAt)
    }

    // ── POST /api/auth/native/mfa: the status map ────────────────────────────

    /// ⛔ STATUS BY STATUS, READ OFF THE ROUTE, AND THE TWO REFUSALS MUST NOT CROSS. A
    /// wrong code (401) keeps the ticket, so the sheet stays open; a ticket refusal
    /// (400: expired, spent, another install) means start again from the Apple sheet.
    func testTheMfaStatusMap() async throws {
        let grant = try Fixture.recorded("district-native-mfa.json")
        let rows = [
            Row(200, grant, .success(Fixture.grant)),
            Row(200, #"{"success":true}"#, .transportFailure),
            Row(200, "<html>captive portal</html>", .transportFailure),
            Row(400, #"{"error":"invalid_grant","code":"invalid_credentials"}"#, .ticketRejected),
            Row(401, #"{"error":"invalid_credentials","code":"invalid_credentials"}"#, .invalidCode),
            Row(429, #"{"error":"Too many requests. Please try again shortly."}"#, .rateLimited),
            // The route answers none of these; all are ambiguous.
            Row(403, "{}", .transportFailure),
            Row(404, "", .transportFailure),
            Row(500, #"{"error":"server_error"}"#, .transportFailure),
            Row(503, "", .transportFailure),
        ]

        for row in rows {
            let client = makeClient(TestTransport(json: row.body, status: row.status))
            let result = await client.submitMfaCode(Fixture.mfaRequest)
            XCTAssertEqual(result, row.expected, "HTTP \(row.status)", line: row.line)
        }
    }

    func testA200WithNoBodyIsAmbiguous() async {
        let result = await makeClient(TestTransport(status: 200)).submitMfaCode(Fixture.mfaRequest)

        XCTAssertEqual(result, .transportFailure)
    }

    /// ⚠️ EVERY I/O FAILURE IS ONE OUTCOME. Whether to send the code again is the
    /// person's decision, made on the sheet.
    func testEveryIoFailureIsTransportFailure() async {
        let errors: [any Error] = [
            URLError(.notConnectedToInternet),
            URLError(.timedOut),
            StubTransportError(isProvablyUnsent: true),
            TransportStub.offline,
        ]

        for error in errors {
            let result = await makeClient(TestTransport(throwing: error)).submitMfaCode(Fixture.mfaRequest)
            XCTAssertEqual(result, .transportFailure, "\(error)")
        }
    }

    // ── POST /api/auth/native/mfa: the request ───────────────────────────────

    /// ⛔ THE ROUTE'S FIVE KEYS, THE TICKET VERBATIM. `deviceId` and `platform` must be
    /// the Apple leg's, since the ticket is bound to both.
    func testTheBodyIsTheRouteSchema() async throws {
        let transport = TestTransport(json: "{}", status: 401)

        _ = await makeClient(transport).submitMfaCode(Fixture.mfaRequest)

        let body = try XCTUnwrap(JSONWire.decode(transport.lastRequest?.body))
        guard case let .object(fields) = body else { return XCTFail("the body is not a JSON object") }
        XCTAssertEqual(Set(fields.keys), ["mfaTicket", "code", "deviceId", "deviceName", "platform"])
        XCTAssertEqual(body["mfaTicket"]?.stringValue, Fixture.ticket)
        XCTAssertEqual(body["code"]?.stringValue, "123456")
        XCTAssertEqual(body["deviceId"]?.stringValue, "install-0123456789")
        XCTAssertEqual(body["deviceName"]?.stringValue, "Test iPhone")
        XCTAssertEqual(body["platform"]?.stringValue, "ios")
    }

    /// ⛔ OMITTED, NOT NULL, and the Mac says so: a ticket minted for `macos` is refused
    /// with any other platform.
    func testTheDeviceNameIsOmittedAndThePlatformIsTheCallers() async throws {
        let transport = TestTransport(json: "{}", status: 401)
        let request = NativeMfaRequest(
            challenge: Fixture.challenge,
            code: "ABCDE-FGHJK",
            deviceId: "install-0123456789",
            deviceName: nil,
            platform: .macos
        )

        _ = await makeClient(transport).submitMfaCode(request)

        let body = try XCTUnwrap(JSONWire.decode(transport.lastRequest?.body))
        guard case let .object(fields) = body else { return XCTFail("the body is not a JSON object") }
        XCTAssertEqual(Set(fields.keys), ["mfaTicket", "code", "deviceId", "platform"])
        XCTAssertEqual(body["platform"]?.stringValue, "macos")
        XCTAssertEqual(body["code"]?.stringValue, "ABCDE-FGHJK")
    }

    /// ⛔ NO BEARER, ONE REQUEST, ITS OWN PATH, REDIRECTS FOLLOWED, NOTHING IN THE URL.
    /// The ticket is a credential and must never reach a query string.
    func testItPostsOnceToItsOwnPathWithNoBearer() async {
        let transport = TestTransport(json: "{}", status: 401)

        _ = await makeClient(transport).submitMfaCode(Fixture.mfaRequest)

        XCTAssertEqual(NativeAuthPaths.mfa, ["api", "auth", "native", "mfa"])
        XCTAssertEqual(transport.recorded.count, 1)
        XCTAssertEqual(transport.lastRequest?.method, .post)
        XCTAssertEqual(transport.lastRequest?.url.absoluteString, "https://auth.example.test/api/auth/native/mfa")
        XCTAssertNil(transport.lastRequest?.headers["Authorization"])
        XCTAssertEqual(transport.lastRequest?.headers["Content-Type"], "application/json; charset=utf-8")
        XCTAssertEqual(transport.lastFollowedRedirects, true)
        XCTAssertNil(transport.lastRequest?.url.query)
    }
}
