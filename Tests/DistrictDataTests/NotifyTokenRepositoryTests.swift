import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// Minting the notify-read token under the app's own session.
final class NotifyTokenRepositoryTests: XCTestCase {
    func testAMintPostsAnEmptyObjectUnderTheSessionAndReturnsTheToken() async {
        let transport = RepositoryTransport(
            json: #"{"success":true,"token":"contract-notify-read-jwt","expiresAt":"2026-11-23T00:00:00.000Z"}"#
        )

        let result = await NotifyTokenRepository(client: .repositoryTest(transport)).mint()

        XCTAssertEqual(
            result.successOnly,
            NotifyTokenResponse(success: true, token: "contract-notify-read-jwt", expiresAt: "2026-11-23T00:00:00.000Z")
        )
        XCTAssertEqual(transport.requests.first?.method, .post)
        XCTAssertEqual(transport.requestedURLs, ["https://www.distronode.com/api/auth/native/notify-token"])
        XCTAssertEqual(transport.bodies, ["{}"])
        XCTAssertEqual(transport.requests.first?.headers["Authorization"], "Bearer session-token")
    }

    /// ⚠️ A BLANK TOKEN IS CONTRACT DRIFT, NOT A CREDENTIAL. Stored for the extension it
    /// would make every sender lookup a 401 that reads like an expiry.
    func testABlankTokenIsADecodeFailure() async {
        let transport = RepositoryTransport(
            json: #"{"success":true,"token":" ","expiresAt":"2026-11-23T00:00:00.000Z"}"#
        )

        let result = await NotifyTokenRepository(client: .repositoryTest(transport)).mint()

        XCTAssertEqual(result.failureOnly, .decoding("NotifyTokenResponse carried no token"))
    }

    func testAMintThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport(
            json: #"{"success":false,"token":"t","expiresAt":"2026-11-23T00:00:00.000Z"}"#
        )

        let result = await NotifyTokenRepository(client: .repositoryTest(transport)).mint()

        XCTAssertEqual(result.failureOnly, .decoding("NotifyTokenResponse did not affirm success=true"))
    }

    /// ⚠️ A 401 IS "not a native session"; it passes through for the app to keep what it
    /// had.
    func testANonNativeCallerIsRefused() async {
        let transport = RepositoryTransport(json: #"{"success":false,"error":"Unauthorized"}"#, status: 401)

        let result = await NotifyTokenRepository(client: .repositoryTest(transport)).mint()

        XCTAssertEqual(result.failureOnly?.httpStatus, 401)
        XCTAssertEqual(transport.requests.count, 1)
    }
}
