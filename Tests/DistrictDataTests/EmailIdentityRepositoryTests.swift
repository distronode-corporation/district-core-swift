import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// The workspace's email identity: the read with the caller's address, the write that echoes
/// the two values, and the refusals that never reach the route.
final class EmailIdentityRepositoryTests: XCTestCase {
    private static func json(_ body: String, _ status: Int = 200) -> HTTPResponse {
        HTTPResponse(statusCode: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }

    private static let read = #"""
    {"success":true,"senderName":"Contract Plumbing","replyTo":"office@contract.test",
     "memberEmail":"contract@distronode.test"}
    """#

    /// The read decodes all four keys, and an unset value is `""` rather than null.
    func testTheReadDecodesTheIdentityAndAsksTheRightURL() async {
        let transport = RepositoryTransport([
            Self.json(Self.read),
            Self.json(#"{"success":true,"senderName":"","replyTo":"","memberEmail":"ada@contract.test"}"#),
        ])
        let repository = WorkspaceRepository(client: .repositoryTest(transport))

        let set = await repository.emailIdentity(workspaceId: "ws_1")
        let unset = await repository.emailIdentity(workspaceId: "ws_1")

        XCTAssertEqual(
            set.successOnly,
            EmailIdentityResponse(
                success: true,
                senderName: "Contract Plumbing",
                replyTo: "office@contract.test",
                memberEmail: "contract@distronode.test"
            )
        )
        XCTAssertEqual(unset.successOnly?.replyTo, "")
        XCTAssertEqual(unset.successOnly?.senderName, "")
        XCTAssertEqual(transport.requests.first?.method, .get)
        XCTAssertEqual(transport.bodies, [])
        XCTAssertEqual(
            transport.requestedURLs.first,
            "https://www.distronode.com/api/district/workspace/email-identity?workspaceId=ws_1"
        )
    }

    /// ⛔ A `success:false` ON A 200 IS NOT AN IDENTITY, on either verb.
    func testABodyThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport([
            Self.json(#"{"success":false,"senderName":"","replyTo":"","memberEmail":"a@b.test"}"#),
            Self.json(#"{"success":false,"senderName":"","replyTo":""}"#),
        ])
        let repository = WorkspaceRepository(client: .repositoryTest(transport))

        let read = await repository.emailIdentity(workspaceId: "ws_1")
        let saved = await repository.saveEmailIdentity(workspaceId: "ws_1", senderName: "", replyTo: nil)

        XCTAssertEqual(read.failureOnly, .decoding("EmailIdentityResponse did not affirm success=true"))
        XCTAssertEqual(saved.failureOnly, .decoding("EmailIdentitySaveResponse did not affirm success=true"))
    }

    /// ⛔ nil IS DROPPED AND `""` IS SENT, so a clear and a leave-alone are different bodies,
    /// and the echo is the new baseline.
    func testTheSaveSendsOnlyWhatChangedAndAdoptsTheEcho() async {
        let transport = RepositoryTransport([
            Self.json(#"{"success":true,"senderName":"Contract Plumbing","replyTo":"office@contract.test"}"#),
            Self.json(#"{"success":true,"senderName":"Contract Plumbing","replyTo":""}"#),
        ])
        let repository = WorkspaceRepository(client: .repositoryTest(transport))

        let named = await repository.saveEmailIdentity(
            workspaceId: "ws_1",
            senderName: "Contract Plumbing",
            replyTo: nil
        )
        let cleared = await repository.saveEmailIdentity(workspaceId: "ws_1", senderName: nil, replyTo: "")

        XCTAssertEqual(
            named.successOnly,
            EmailIdentitySaveResponse(success: true, senderName: "Contract Plumbing", replyTo: "office@contract.test")
        )
        XCTAssertEqual(cleared.successOnly?.replyTo, "")
        XCTAssertEqual(transport.requests.map(\.method), [.patch, .patch])
        XCTAssertEqual(transport.bodies, [
            #"{"senderName":"Contract Plumbing","workspaceId":"ws_1"}"#,
            #"{"replyTo":"","workspaceId":"ws_1"}"#,
        ])
    }

    /// ⛔ THREE BODIES THE ROUTE WOULD ANSWER 400 FOR, REFUSED WITHOUT A REQUEST: neither
    /// field, a sender name over 100 and a Reply-to over 320, counted in UTF-16 as the route
    /// counts them. The bounds themselves are accepted.
    func testOutOfBoundsSavesAreRefusedBeforeTheyAreSent() async {
        let transport = RepositoryTransport([
            Self.json(#"{"success":true,"senderName":"x","replyTo":"y"}"#),
        ])
        let repository = WorkspaceRepository(client: .repositoryTest(transport))
        // 50 two-unit characters is 100 UTF-16 units, plus one more is over.
        let longName = String(repeating: "\u{1F600}", count: 50) + "a"
        let longReplyTo = String(repeating: "a", count: 321)

        let neither = await repository.saveEmailIdentity(workspaceId: "ws_1", senderName: nil, replyTo: nil)
        let name = await repository.saveEmailIdentity(workspaceId: "ws_1", senderName: longName, replyTo: nil)
        let reply = await repository.saveEmailIdentity(workspaceId: "ws_1", senderName: nil, replyTo: longReplyTo)

        XCTAssertEqual(
            neither.failureOnly,
            .decoding("saveEmailIdentity was given neither field, which the route answers 400")
        )
        XCTAssertEqual(name.failureOnly, .decoding("saveEmailIdentity was given a sender name over 100 characters"))
        XCTAssertEqual(reply.failureOnly, .decoding("saveEmailIdentity was given a Reply-to over 320 characters"))
        XCTAssertTrue(transport.requestedURLs.isEmpty)

        let atBounds = await repository.saveEmailIdentity(
            workspaceId: "ws_1",
            senderName: String(repeating: "a", count: 100),
            replyTo: String(repeating: "a", count: 320)
        )
        XCTAssertNotNil(atBounds.successOnly)
        XCTAssertEqual(transport.requestedURLs.count, 1)
    }

    /// ⚠️ THE ROUTE'S REFUSALS KEEP THEIR CODE AND STATUS: a Reply-to that is not one address,
    /// a viewer's write, and a workspace that is gone.
    func testRefusalsKeepTheirCodeAndStatus() async {
        let transport = RepositoryTransport([
            Self.json(
                #"{"success":false,"error":"The reply-to address must be one email address.","#
                    + #""code":"invalid_request"}"#,
                400
            ),
            Self.json(#"{"success":false,"error":"Forbidden","code":"forbidden"}"#, 403),
            Self.json(#"{"success":false,"error":"Workspace not found","code":"workspace_not_found"}"#, 404),
        ])
        let repository = WorkspaceRepository(client: .repositoryTest(transport))

        let invalid = await repository.saveEmailIdentity(
            workspaceId: "ws_1",
            senderName: nil,
            replyTo: "a@b.test, c@d.test"
        )
        let viewer = await repository.saveEmailIdentity(workspaceId: "ws_1", senderName: "x", replyTo: nil)
        let gone = await repository.emailIdentity(workspaceId: "ws_1")

        XCTAssertEqual(
            [invalid.failureOnly?.code, viewer.failureOnly?.code, gone.failureOnly?.code],
            ["invalid_request", "forbidden", "workspace_not_found"]
        )
        XCTAssertEqual(
            [invalid.failureOnly?.httpStatus, viewer.failureOnly?.httpStatus, gone.failureOnly?.httpStatus],
            [400, 403, 404]
        )
    }
}
