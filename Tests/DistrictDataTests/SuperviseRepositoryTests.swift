import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// The listen seat and the takeover, through ``CallsRepository``.
///
/// ⛔ NO TEST HERE EXPECTS A SECOND REQUEST. Neither credential is retried: a late listen
/// seat joins a person to a call they left, and a late takeover is a live microphone in
/// a customer's call. Each refusal asserts exactly one request went out.
///
/// ⚠️ THE BODIES ARE MODELLED FROM THE ROUTE SOURCE (`calls/token/route.ts` for a
/// `Call.id`, `calls/[callId]/takeover/route.ts`) until the contract corpus records them.
final class SuperviseRepositoryTests: XCTestCase {
    private static let callId = SupervisedCallID("3f2a9c1e-call")!

    // MARK: - Listen

    func testAListenPostsTheCallIdAsTheRoomAndDecodesTheSeat() async throws {
        let transport = RepositoryTransport(
            json: #"{"success":true,"token":"listen-jwt","url":"wss://livekit-wss.distronode.com"}"#
        )

        let result = await CallsRepository(client: .repositoryTest(transport)).monitor(callId: Self.callId)

        let seat = try XCTUnwrap(result.successOnly)
        XCTAssertEqual(seat.token, "listen-jwt")
        XCTAssertEqual(seat.url, "wss://livekit-wss.distronode.com")
        XCTAssertEqual(transport.requests.first?.method, .post)
        XCTAssertEqual(transport.requestedURLs, ["https://www.distronode.com/api/district/calls/token"])
        XCTAssertEqual(transport.bodies, [#"{"identity":"ios","roomName":"3f2a9c1e-call"}"#])
    }

    func testAListenRefusalCarriesItsCodeAndIsOneRequest() async {
        let transport = RepositoryTransport(
            json: #"{"success":false,"error":"Call room not found","code":"room_not_found"}"#,
            status: 404
        )

        let result = await CallsRepository(client: .repositoryTest(transport)).monitor(callId: Self.callId)

        XCTAssertEqual(result.failureOnly?.httpStatus, 404)
        XCTAssertEqual(result.failureOnly?.code, "room_not_found")
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testAListenSeatThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport(json: #"{"success":false,"token":"t","url":"wss://x"}"#)

        let result = await CallsRepository(client: .repositoryTest(transport)).monitor(callId: Self.callId)

        XCTAssertEqual(result.failureOnly, .decoding("CallMonitorResponse did not affirm success=true"))
    }

    /// ⛔ `""` DECODES, AND JOINING ON IT WOULD READ AS A MEDIA FAILURE on a screen already
    /// showing a listener.
    func testABlankListenCredentialIsADecodeFailure() async {
        for body in [#"{"success":true,"token":" ","url":"wss://x"}"#, #"{"success":true,"token":"t","url":""}"#] {
            let transport = RepositoryTransport(json: body)

            let result = await CallsRepository(client: .repositoryTest(transport)).monitor(callId: Self.callId)

            XCTAssertEqual(result.failureOnly, .decoding("CallMonitorResponse carried no join credential"), body)
        }
    }

    // MARK: - Take over

    func testATakeoverPostsTheCallInThePathAndDecodesTheCoachSeat() async throws {
        let transport = RepositoryTransport(
            json: #"{"success":true,"url":"wss://livekit-wss.distronode.com","token":"coach-jwt","#
                + #""roomName":"call_ws-1_inbound-1"}"#
        )

        let result = await CallsRepository(client: .repositoryTest(transport))
            .takeOver(workspaceId: "ws_1", callId: "call_1")

        let seat = try XCTUnwrap(result.successOnly)
        XCTAssertEqual(seat.token, "coach-jwt")
        XCTAssertEqual(seat.url, "wss://livekit-wss.distronode.com")
        XCTAssertEqual(seat.roomName, "call_ws-1_inbound-1")
        XCTAssertEqual(transport.requestedURLs, ["https://www.distronode.com/api/district/calls/call_1/takeover"])
        XCTAssertEqual(transport.bodies, [#"{"workspaceId":"ws_1"}"#])
    }

    /// ⛔ "COULD NOT CHECK" (503) AND "GONE" (409) STAY DISTINCT CODES, and neither is retried.
    func testTakeoverRefusalsCarryTheirCodesAndAreOneRequestEach() async {
        let cases: [(Int, String)] = [
            (409, "call_not_in_progress"), (409, "call_has_no_room"), (404, "call_not_found"),
            (503, "service_unavailable"),
        ]
        for (status, code) in cases {
            let transport = RepositoryTransport(
                json: #"{"success":false,"error":"x","code":""# + code + #""}"#,
                status: status
            )

            let result = await CallsRepository(client: .repositoryTest(transport))
                .takeOver(workspaceId: "ws_1", callId: "call_1")

            XCTAssertEqual(result.failureOnly?.httpStatus, status, code)
            XCTAssertEqual(result.failureOnly?.code, code)
            XCTAssertEqual(transport.requests.count, 1, code)
        }
    }

    func testATakeoverThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport(json: #"{"success":false,"url":"wss://x","token":"t","roomName":"r"}"#)

        let result = await CallsRepository(client: .repositoryTest(transport))
            .takeOver(workspaceId: "ws_1", callId: "call_1")

        XCTAssertEqual(result.failureOnly, .decoding("CallTakeoverResponse did not affirm success=true"))
    }

    func testABlankCoachCredentialIsADecodeFailure() async {
        let transport = RepositoryTransport(json: #"{"success":true,"url":"wss://x","token":"","roomName":"r"}"#)

        let result = await CallsRepository(client: .repositoryTest(transport))
            .takeOver(workspaceId: "ws_1", callId: "call_1")

        XCTAssertEqual(result.failureOnly, .decoding("CallTakeoverResponse carried no join credential"))
    }
}
