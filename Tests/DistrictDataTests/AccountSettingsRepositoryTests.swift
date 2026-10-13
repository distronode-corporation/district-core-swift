@testable import DistrictData
import DistrictL10n
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

final class AccountSettingsRepositoryTests: XCTestCase {
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

        let unaffirmed = RepositoryTransport(json: #"{"success":false}"#)
        let decoding = await AccountSettingsRepository(client: .repositoryTest(unaffirmed)).saveLocale(.en)
        XCTAssertEqual(decoding.failureOnly, .decoding("AccountSettingsResponse did not affirm success=true"))
    }
}
