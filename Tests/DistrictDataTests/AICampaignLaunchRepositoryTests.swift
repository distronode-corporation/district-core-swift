import DistrictData
import DistrictL10n
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// The AI campaign launcher: the web's body exactly, the route's three limits refused
/// before anything is sent, and an answer whose `success` is not a call going out.
final class AICampaignLaunchRepositoryTests: XCTestCase {
    private let answer = #"{"success":true,"results":["#
        + #"{"contactId":"c_1","callId":"CA1","status":"queued","provider":"twilio","accountId":"acct_1"},"#
        + #"{"contactId":"c_2","status":"skipped","error":"Opted out","code":"auto_dial_contact_opted_out"},"#
        + #"{"contactId":"c_3","status":"failed","error":"Something went wrong. Please try again."}]}"#

    /// ⛔ FIVE KEYS AND NEVER A `from`: the route picks the number the calls come from.
    func testItSendsTheWebsBodyAndDecodesEachContact() async throws {
        let transport = RepositoryTransport(queue: [answer])
        let campaigns = CampaignsRepository(client: .repositoryTest(transport))
        let launched = try await campaigns.launchAICampaign(
            workspaceId: "ws_1",
            contactIds: ["c_1", "c_2", "c_3"],
            prompt: "  Confirm Tuesday's appointment.",
            accountId: "acct_1"
        ).get()
        XCTAssertEqual(transport.requestedURLs, ["https://www.distronode.com/api/district/calls/outbound"])
        XCTAssertEqual(transport.requests.map(\.method), [.post])
        // The prompt travels exactly as written, leading spaces and all.
        XCTAssertEqual(transport.bodies, [
            #"{"accountId":"acct_1","channel":"voice","contactIds":["c_1","c_2","c_3"],"#
                + #""prompt":"  Confirm Tuesday's appointment.","workspaceId":"ws_1"}"#,
        ])
        XCTAssertFalse(try XCTUnwrap(transport.bodies.first).contains("from"))
        XCTAssertEqual(launched.queuedCount, 1)
        XCTAssertEqual(launched.results.map(\.status), [.queued, .skipped, .failed])
        XCTAssertEqual(launched.results[0].callId, "CA1")
        XCTAssertEqual(launched.results[1].code, "auto_dial_contact_opted_out")
    }

    /// No account: the key is dropped, as the web drops `undefined`.
    func testANilAccountIsDroppedFromTheBody() async {
        let transport = RepositoryTransport(queue: [#"{"success":true,"results":[]}"#])
        let campaigns = CampaignsRepository(client: .repositoryTest(transport))
        let launched = await campaigns.launchAICampaign(workspaceId: "ws_1", contactIds: ["c_1"], prompt: "Hi")
        XCTAssertEqual(launched.successOnly?.queuedCount, 0)
        XCTAssertEqual(transport.bodies, [
            #"{"channel":"voice","contactIds":["c_1"],"prompt":"Hi","workspaceId":"ws_1"}"#,
        ])
    }

    /// ⛔ THE THREE LIMITS ARE REFUSED HERE AND NOTHING IS SENT. 100 contacts is allowed;
    /// 101 is not.
    func testTheRoutesOwnLimitsAreRefusedBeforeSending() async {
        let transport = RepositoryTransport(queue: [#"{"success":true,"results":[]}"#])
        let campaigns = CampaignsRepository(client: .repositoryTest(transport))
        let tooMany = (0 ... 100).map { "c_\($0)" }
        let none = await campaigns.launchAICampaign(workspaceId: "ws_1", contactIds: [], prompt: "Hi")
        let over = await campaigns.launchAICampaign(workspaceId: "ws_1", contactIds: tooMany, prompt: "Hi")
        let blank = await campaigns.launchAICampaign(workspaceId: "ws_1", contactIds: ["c_1"], prompt: " \n\t")
        XCTAssertEqual(none.failureOnly, .http(status: 400, message: CampaignCopy.noContacts))
        XCTAssertEqual(over.failureOnly, .http(status: 400, message: CampaignCopy.tooManyContacts))
        XCTAssertEqual(blank.failureOnly, .http(status: 400, message: CampaignCopy.promptBlank))
        XCTAssertTrue(transport.requests.isEmpty, "a refused launch must not reach the network")

        let atTheLimit = await campaigns.launchAICampaign(
            workspaceId: "ws_1",
            contactIds: Array(tooMany.dropLast()),
            prompt: "Hi"
        )
        XCTAssertNotNil(atTheLimit.successOnly)
        XCTAssertEqual(transport.requests.count, 1)
    }

    /// The refusals are the core's own sentences, so they survive a French screen.
    func testTheRefusalsReadInFrench() async {
        let campaigns = CampaignsRepository(client: .repositoryTest(RepositoryTransport(queue: [])))
        let refused = await L10nRuntime.$scoped.withValue(.frCA) {
            await campaigns.launchAICampaign(workspaceId: "ws_1", contactIds: [], prompt: "Hi")
        }
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(refused.failureOnly?.localizedMessage, "Choisissez au moins un contact à appeler.")
        }
    }

    /// ⚠️ A WORKSPACE REFUSAL IS THE WHOLE BATCH, WITH ITS CODE, and a body that does not
    /// affirm success is a decoding failure rather than an empty campaign.
    func testABatchRefusalKeepsItsCodeAndAnUnaffirmedBodyFails() async {
        let transport = RepositoryTransport([
            HTTPResponse(
                statusCode: 429,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"success":false,"error":"Too many","code":"rate_limited"}"#.utf8)
            ),
            HTTPResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"success":false,"results":[]}"#.utf8)
            ),
        ])
        let campaigns = CampaignsRepository(client: .repositoryTest(transport))
        let limited = await campaigns.launchAICampaign(workspaceId: "ws_1", contactIds: ["c_1"], prompt: "Hi")
        let unaffirmed = await campaigns.launchAICampaign(workspaceId: "ws_1", contactIds: ["c_1"], prompt: "Hi")
        XCTAssertEqual(limited.failureOnly?.code, "rate_limited")
        XCTAssertEqual(limited.failureOnly?.httpStatus, 429)
        XCTAssertEqual(unaffirmed.failureOnly, .decoding("AICampaignLaunchResponse did not affirm success=true"))
    }
}
