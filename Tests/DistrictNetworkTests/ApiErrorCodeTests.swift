import DistrictL10n
import DistrictModel
@testable import DistrictNetwork
import Foundation
import XCTest

/// The error code a refusal carries, from its body or its header, and the language
/// every request asks for.
final class ApiErrorCodeTests: XCTestCase {
    // MARK: - Where the code comes from

    /// ⛔ THE BODY WINS, as on the website: a route that writes a code into its body is
    /// the specific answer, and a header may have been stamped by a guard wrapping it.
    func testTheBodyCodeWinsOverTheHeader() {
        let body = Data(#"{"error":"Too fast","code":"rate_limited"}"#.utf8)
        let error = ApiErrorNormalizer.apiError(statusCode: 429, body: body, headerCode: "unauthorized")
        XCTAssertEqual(error, .http(status: 429, message: "Too fast", code: "rate_limited"))
    }

    /// The header carries the code where the body is pinned by a fixture and cannot.
    func testTheHeaderCodeIsReadWhenTheBodyHasNone() {
        let bare = Data(#"{"error":"Unauthorized"}"#.utf8)
        XCTAssertEqual(
            ApiErrorNormalizer.apiError(statusCode: 401, body: bare, headerCode: "session_expired").code,
            "session_expired"
        )
        let blank = Data(#"{"error":"Unauthorized","code":"  "}"#.utf8)
        XCTAssertEqual(
            ApiErrorNormalizer.apiError(statusCode: 401, body: blank, headerCode: "session_expired").code,
            "session_expired"
        )
        XCTAssertEqual(ApiErrorNormalizer.apiError(statusCode: 502, body: nil, headerCode: "unknown").code, "unknown")
    }

    /// A blank code names nothing, on either carrier.
    func testABlankCodeIsNoCode() {
        XCTAssertNil(ApiErrorNormalizer.apiError(statusCode: 500, body: nil, headerCode: "").code)
        XCTAssertNil(ApiErrorNormalizer.apiError(statusCode: 500, body: nil, headerCode: " \n").code)
        XCTAssertNil(ApiErrorNormalizer.apiError(statusCode: 500, body: nil).code)
        XCTAssertNil(ApiErrorNormalizer.apiError(statusCode: 200, body: nil, headerCode: "unknown").code)
    }

    /// ⛔ THROUGH THE CLIENT, WITH THE HEADER IN WHATEVER CASE THE TRANSPORT GAVE IT.
    /// Darwin canonicalises header names and the Linux transport does not.
    func testTheClientReadsTheHeaderCodeOnEitherPath() async {
        let headers = ["x-distronode-error-code": "rate_limited", "Content-Type": "application/json"]
        let mapped = await ApiClient.test(TestTransport(
            status: 429,
            headers: headers,
            body: Data(#"{"error":"Too many requests."}"#.utf8)
        )).send(DistrictEndpoints.devices())
        XCTAssertEqual(mapped.failureOnly, .http(status: 429, message: "Too many requests.", code: "rate_limited"))

        let unmapped = await ApiClient.test(TestTransport(status: 429, headers: headers, body: nil))
            .sendUnmapped(DistrictEndpoints.devices())
        XCTAssertEqual(unmapped.successOnly?.errorCodeHeader, "rate_limited")
        XCTAssertEqual(unmapped.successOnly?.body, Data())

        let typed = await ApiClient.test(TestTransport(status: 429, headers: headers, body: nil))
            .send(DistrictEndpoints.devices(), as: DevicesResponse.self)
        XCTAssertEqual(typed.failureOnly?.code, "rate_limited")
    }

    // MARK: - Accept-Language

    /// `en` until an app turns French on, then the tag of the language it shows.
    func testEveryRequestSendsTheResolvedLanguage() async {
        let english = TestTransport(json: #"{"success":true,"devices":[]}"#)
        _ = await ApiClient.test(english).send(DistrictEndpoints.devices())
        XCTAssertEqual(english.lastRequest?.headers["Accept-Language"], "en")

        let french = TestTransport(json: #"{"success":true,"devices":[]}"#)
        await L10nRuntime.$scoped.withValue(.frCA) {
            _ = await ApiClient.test(french).send(DistrictEndpoints.devices())
        }
        XCTAssertEqual(french.lastRequest?.headers["Accept-Language"], "fr-CA")
    }

    /// The unauthenticated sign-in routes too: the server's refusal sentences are the
    /// first text a French reader sees.
    func testTheSignInRoutesSendTheResolvedLanguage() async {
        let transport = TestTransport(status: 503)
        await L10nRuntime.$scoped.withValue(.frCA) {
            _ = await TestNativeAuthClient(baseURL: URL(string: "https://auth.example.test")!, transport: transport)
                .revoke(refreshToken: "rt-opaque")
        }
        XCTAssertEqual(transport.lastRequest?.headers["Accept-Language"], "fr-CA")
    }

    // MARK: - The settings write

    /// ⛔ ONLY `locale`, and as the route's enum spells it, never the language tag.
    func testTheSettingsWriteSendsOnlyTheLocale() throws {
        let descriptor = DistrictEndpoints.saveLocale(.en)
        XCTAssertEqual(descriptor.method, .post)
        XCTAssertEqual(ApiPath.build(descriptor.segments), "/api/settings")
        guard case let .json(value) = descriptor.body else { return XCTFail("expected a JSON body") }
        let encoded = try XCTUnwrap(String(data: JSONWire.encode(value), encoding: .utf8))
        XCTAssertEqual(encoded, #"{"profile":{"locale":"en"}}"#)
    }
}
