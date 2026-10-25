import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// A Live Activity's push token, handed to the server for one call, and the device's
/// push-to-start token, handed over for none.
///
/// ⛔ NO TEST HERE EXPECTS A SECOND REQUEST, and none may be added. ActivityKit hands over
/// each new token and each is sent once; a retry loop would outlive the call. Each test
/// asserts exactly one request went out, whatever the answer.
final class LiveActivityRepositoryTests: XCTestCase {
    func testARegistrationPostsTheCallInThePathAndTheWorkspaceAndTokenInTheBody() async {
        let transport = RepositoryTransport(json: #"{"success":true}"#)

        let result = await CallsRepository(client: .repositoryTest(transport))
            .registerLiveActivity(workspaceId: "ws_1", callId: "call_1", token: "0a1b2c")

        XCTAssertNotNil(result.successOnly)
        XCTAssertEqual(transport.requests.first?.method, .post)
        XCTAssertEqual(transport.requestedURLs, ["https://www.distronode.com/api/district/calls/call_1/live-activity"])
        XCTAssertEqual(transport.bodies, [#"{"token":"0a1b2c","workspaceId":"ws_1"}"#])
    }

    /// ⚠️ 404 IS THE CALL ENDING FIRST. It reaches the caller as a failure for a log line,
    /// and nothing is sent again.
    func testACallThatAlreadyEndedIsOneFailedRequestAndNoRetry() async {
        let transport = RepositoryTransport(
            json: #"{"success":false,"error":"Call not found","code":"call_not_found"}"#,
            status: 404
        )

        let result = await CallsRepository(client: .repositoryTest(transport))
            .registerLiveActivity(workspaceId: "ws_1", callId: "call_1", token: "0a1b2c")

        XCTAssertEqual(result.failureOnly?.httpStatus, 404)
        XCTAssertEqual(result.failureOnly?.code, "call_not_found")
        XCTAssertEqual(transport.requests.count, 1)
    }

    /// ⚠️ A 503 IS NOT RETRIED EITHER: the activity still updates locally while the app is
    /// awake, and the next rotated token is the next attempt.
    func testAServerFailureIsOneRequest() async {
        let transport = RepositoryTransport(
            json: #"{"success":false,"error":"x","code":"service_unavailable"}"#,
            status: 503
        )

        let result = await CallsRepository(client: .repositoryTest(transport))
            .registerLiveActivity(workspaceId: "ws_1", callId: "call_1", token: "0a1b2c")

        XCTAssertEqual(result.failureOnly?.httpStatus, 503)
        XCTAssertEqual(transport.requests.count, 1)
    }

    /// ⛔ A 200 THAT DOES NOT AFFIRM SUCCESS IS CONTRACT DRIFT, not a token stored.
    func testARegistrationThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport(json: #"{"success":false}"#)

        let result = await CallsRepository(client: .repositoryTest(transport))
            .registerLiveActivity(workspaceId: "ws_1", callId: "call_1", token: "0a1b2c")

        XCTAssertEqual(result.failureOnly, .decoding("LiveActivityResponse did not affirm success=true"))
    }

    // MARK: - The push-to-start token

    /// ⚠️ NO CALL ANYWHERE: the token is the user's, and the workspace only routes it.
    func testAStartTokenPostsTheWorkspaceAndTokenToItsOwnRoute() async {
        let transport = RepositoryTransport(json: #"{"success":true}"#)

        let result = await CallsRepository(client: .repositoryTest(transport))
            .registerLiveActivityStartToken(workspaceId: "ws_1", token: "9f00")

        XCTAssertNotNil(result.successOnly)
        XCTAssertEqual(transport.requests.first?.method, .post)
        XCTAssertEqual(transport.requestedURLs, ["https://www.distronode.com/api/district/live-activity/start-token"])
        XCTAssertEqual(transport.bodies, [#"{"token":"9f00","workspaceId":"ws_1"}"#])
    }

    func testAStartTokenRefusalIsOneRequestWithItsCode() async {
        let transport = RepositoryTransport(
            json: #"{"success":false,"error":"Missing parameters","code":"invalid_request"}"#,
            status: 400
        )

        let result = await CallsRepository(client: .repositoryTest(transport))
            .registerLiveActivityStartToken(workspaceId: "ws_1", token: "")

        XCTAssertEqual(result.failureOnly?.code, "invalid_request")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testAStartTokenThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport(json: #"{"success":false}"#)

        let result = await CallsRepository(client: .repositoryTest(transport))
            .registerLiveActivityStartToken(workspaceId: "ws_1", token: "9f00")

        XCTAssertEqual(result.failureOnly, .decoding("LiveActivityStartTokenResponse did not affirm success=true"))
    }
}
