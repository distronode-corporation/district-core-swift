import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// A person's decline of a ringing call, and a supervisor's whisper on a live one.
///
/// ⛔ NO TEST HERE EXPECTS A SECOND REQUEST, and none may be added. Neither call is
/// retried: a decline is about a ring that may already be over, and a whisper may have
/// reached the agent before its response was lost. Each test asserts exactly one request
/// went out, whatever the answer.
final class DeclineAndWhisperRepositoryTests: XCTestCase {
    // MARK: - The decline

    func testADeclinePostsTheCallInThePathAndTheWorkspaceInTheBody() async {
        let transport = RepositoryTransport(json: #"{"success":true}"#)

        let result = await InboundCallRepository(client: .repositoryTest(transport))
            .decline(callId: "CA1", workspaceId: "ws_1")

        XCTAssertNotNil(result.successOnly)
        XCTAssertEqual(transport.requests.first?.method, .post)
        XCTAssertEqual(transport.requestedURLs, ["https://www.distronode.com/api/district/calls/CA1/decline"])
        XCTAssertEqual(transport.bodies, [#"{"workspaceId":"ws_1"}"#])
    }

    /// ⚠️ 404 IS THE CALL ENDING WHILE THE PHONE RANG. It reaches the caller as a failure
    /// for a log line; the local ring is already over, so nothing is retried.
    func testACallThatAlreadyEndedIsOneFailedRequestAndNoRetry() async {
        let transport = RepositoryTransport(
            json: #"{"success":false,"error":"Call not found","code":"call_not_found"}"#,
            status: 404
        )

        let result = await InboundCallRepository(client: .repositoryTest(transport))
            .decline(callId: "CA1", workspaceId: "ws_1")

        XCTAssertEqual(result.failureOnly?.httpStatus, 404)
        XCTAssertEqual(result.failureOnly?.code, "call_not_found")
        XCTAssertEqual(transport.requests.count, 1)
    }

    /// ⛔ A 200 THAT DOES NOT AFFIRM SUCCESS IS CONTRACT DRIFT, not a decline recorded.
    func testADeclineThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport(json: #"{"success":false}"#)

        let result = await InboundCallRepository(client: .repositoryTest(transport))
            .decline(callId: "CA1", workspaceId: "ws_1")

        XCTAssertEqual(result.failureOnly, .decoding("CallDeclineResponse did not affirm success=true"))
    }

    // MARK: - The whisper

    func testAWhisperPostsTheCallAndTheLineInTheBody() async {
        let transport = RepositoryTransport(json: #"{"success":true}"#)

        let result = await CallsRepository(client: .repositoryTest(transport))
            .whisper(workspaceId: "ws_1", callId: "call_1", text: "The owner will call them back today.")

        XCTAssertNotNil(result.successOnly)
        XCTAssertEqual(transport.requests.first?.method, .post)
        XCTAssertEqual(transport.requestedURLs, ["https://www.distronode.com/api/district/calls/whisper"])
        XCTAssertEqual(
            transport.bodies,
            [#"{"callId":"call_1","whisper":"The owner will call them back today.","workspaceId":"ws_1"}"#]
        )
    }

    /// ⛔ A CALL THAT ENDED IS A FAILURE THE SCREEN NAMES BY ITS CODE, AND IS NOT SENT
    /// AGAIN. The 409 is the route's "no deployment holds this room": the line was not
    /// delivered.
    func testAWhisperToAnEndedCallFailsWithItsCodeAndIsNotRetried() async {
        let transport = RepositoryTransport(
            json: #"{"success":false,"error":"This call has ended. The whisper was not delivered.","#
                + #""code":"call_not_in_progress"}"#,
            status: 409
        )

        let result = await CallsRepository(client: .repositoryTest(transport))
            .whisper(workspaceId: "ws_1", callId: "call_1", text: "Ask what the call is about.")

        XCTAssertEqual(result.failureOnly?.httpStatus, 409)
        XCTAssertEqual(result.failureOnly?.code, "call_not_in_progress")
        XCTAssertEqual(transport.requests.count, 1)
    }

    /// ⚠️ A 503 IS THE ONE FAILURE THAT MAY HAVE BEEN DELIVERED NOWHERE AND IS STILL NOT
    /// RETRIED HERE: whether to send again is the person's call, not this layer's.
    func testAnUnreachableCallingServiceIsOneRequest() async {
        let transport = RepositoryTransport(
            json: #"{"success":false,"error":"x","code":"service_unavailable"}"#,
            status: 503
        )

        let result = await CallsRepository(client: .repositoryTest(transport))
            .whisper(workspaceId: "ws_1", callId: "call_1", text: "Ask what the call is about.")

        XCTAssertEqual(result.failureOnly?.code, "service_unavailable")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testAWhisperThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport(json: #"{"success":false}"#)

        let result = await CallsRepository(client: .repositoryTest(transport))
            .whisper(workspaceId: "ws_1", callId: "call_1", text: "x")

        XCTAssertEqual(result.failureOnly, .decoding("WhisperResponse did not affirm success=true"))
    }
}
