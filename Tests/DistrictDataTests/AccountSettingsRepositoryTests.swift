@testable import DistrictData
import DistrictL10n
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

final class AccountSettingsRepositoryTests: XCTestCase {
    /// ⛔ A NULL `locale` IS "NEVER CHOSEN" AND MUST ARRIVE AS NIL, NOT AS ENGLISH.
    func testLoadingTheSettingsGetsTheRouteAndKeepsANullLocale() async throws {
        let transport = RepositoryTransport(json: #"""
        {"profile":{"email":"a@example.com","displayName":"","timezone":"America/Toronto","locale":null},
         "subscription":{"tier":"Free","status":"none"},"region":"us"}
        """#)
        let result = await AccountSettingsRepository(client: .repositoryTest(transport)).loadSettings()

        let settings = try XCTUnwrap(result.successOnly)
        XCTAssertNil(settings.profile.locale)
        XCTAssertNil(settings.subscription.updatedAt)
        XCTAssertEqual(settings.region, "us")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.url.absoluteString, "https://www.distronode.com/api/settings")
    }

    func testARefusedReadIsAFailure() async {
        let refused = RepositoryTransport(
            json: #"{"error":"Failed to load settings","code":"server_error"}"#,
            status: 500
        )
        let failure = await AccountSettingsRepository(client: .repositoryTest(refused)).loadSettings()
        XCTAssertEqual(
            failure.failureOnly,
            .http(status: 500, message: "Failed to load settings", code: "server_error")
        )
    }

    /// ⛔ `fr`, NOT `fr-CA`: the route's schema is the website's two catalogs.
    func testSavingTheLocalePostsTheStoredValue() async throws {
        let transport = RepositoryTransport(json: #"{"success":true,"message":"Settings saved successfully"}"#)
        let result = await AccountSettingsRepository(client: .repositoryTest(transport)).saveLocale(.frCA)

        XCTAssertNil(result.failureOnly)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.url.absoluteString, "https://www.distronode.com/api/settings")
        XCTAssertEqual(request.body.flatMap { String(bytes: $0, encoding: .utf8) }, #"{"profile":{"locale":"fr"}}"#)
    }

    /// The route answers `{error}` with no `success` key on a refusal, and a 200 that
    /// does not affirm success is not a save.
    func testARefusalAndAnUnaffirmedAnswerAreFailures() async {
        let refused = RepositoryTransport(
            json: #"{"error":"Failed to save settings","code":"server_error"}"#,
            status: 500
        )
        let failure = await AccountSettingsRepository(client: .repositoryTest(refused)).saveLocale(.en)
        XCTAssertEqual(
            failure.failureOnly,
            .http(status: 500, message: "Failed to save settings", code: "server_error")
        )

        let unaffirmed = RepositoryTransport(json: #"{"success":false,"message":"Settings saved successfully"}"#)
        let decoding = await AccountSettingsRepository(client: .repositoryTest(unaffirmed)).saveLocale(.en)
        XCTAssertEqual(decoding.failureOnly, .decoding("AccountSettingsSaveResponse did not affirm success=true"))
    }
}
