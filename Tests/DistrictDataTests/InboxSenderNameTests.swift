@testable import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// A pushed message's sender name, as a notification extension reads it.
///
/// ⛔ THE NULL NAME IS DECODED FROM BYTES RATHER THAN FROM A FIXTURE, and that is a
/// property of the corpus: `district-message-sender.json` names a contact, and the
/// corpus is the server's, so the "no named contact" body is pinned here instead.
final class InboxSenderNameTests: XCTestCase {
    /// ⛔ THE CREDENTIAL IS WHATEVER THE CLIENT'S TOKEN PROVIDER ANSWERS, which in the
    /// extension is the notify-read token, never the session. The request is one GET
    /// with the push's workspace in the query and the id a segment ahead of `sender`.
    func testANamedContactResolvesToItsNameUnderTheGivenToken() async {
        let transport = RepositoryTransport(json: #"{"success":true,"name":"Avery Contract"}"#)
        let client = ApiClient(
            baseURL: ApiClient.productionBaseURL,
            transport: transport,
            accessToken: { "notify-read-token" }
        )

        let result = await InboxRepository(client: client).messageSender(workspaceId: "ws_1", messageId: "msg_1")

        XCTAssertEqual(result.successOnly, "Avery Contract")
        XCTAssertEqual(transport.requests.first?.method, .get)
        XCTAssertEqual(
            transport.requestedURLs,
            ["https://www.distronode.com/api/district/messages/msg_1/sender?workspaceId=ws_1"]
        )
        XCTAssertEqual(transport.requests.first?.headers["Authorization"], "Bearer notify-read-token")
        XCTAssertTrue(transport.bodies.isEmpty, "a GET carries no body")
    }

    /// ⚠️ NULL IS "THIS THREAD HAS NO NAMED CONTACT", A SUCCESS, and the extension keeps
    /// its generic text. So is a blank name, which would otherwise be a lock-screen title
    /// of whitespace.
    func testANullOrBlankNameIsNil() async {
        for body in [#"{"success":true,"name":null}"#, #"{"success":true}"#, #"{"success":true,"name":"  "}"#] {
            let transport = RepositoryTransport(json: body)

            let result = await InboxRepository(client: .repositoryTest(transport))
                .messageSender(workspaceId: "ws_1", messageId: "msg_1")

            guard case let .success(name) = result else {
                return XCTFail("\(body) is a success")
            }
            XCTAssertNil(name, body)
        }
    }

    /// ⚠️ A NAME IS TRIMMED, so a stray newline from a contact import does not reach a
    /// notification title.
    func testANameIsTrimmed() async {
        let transport = RepositoryTransport(json: #"{"success":true,"name":" Avery Contract\n"}"#)

        let result = await InboxRepository(client: .repositoryTest(transport))
            .messageSender(workspaceId: "ws_1", messageId: "msg_1")

        XCTAssertEqual(result.successOnly, "Avery Contract")
    }

    /// ⛔ EVERY FAILURE IS ONE REQUEST AND THE GENERIC TEXT: a 401 (an expired token, or
    /// a signed-out session behind it) is not refreshed and not retried.
    func testARefusedTokenIsOneRequestAndAFailure() async {
        let transport = RepositoryTransport(json: #"{"success":false,"error":"Unauthorized"}"#, status: 401)

        let result = await InboxRepository(client: .repositoryTest(transport))
            .messageSender(workspaceId: "ws_1", messageId: "msg_1")

        XCTAssertEqual(result.failureOnly?.httpStatus, 401)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testASenderThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport(json: #"{"success":false,"name":"Avery Contract"}"#)

        let result = await InboxRepository(client: .repositoryTest(transport))
            .messageSender(workspaceId: "ws_1", messageId: "msg_1")

        XCTAssertEqual(result.failureOnly, .decoding("MessageSenderResponse did not affirm success=true"))
    }
}
