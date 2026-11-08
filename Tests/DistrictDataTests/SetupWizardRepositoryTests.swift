@testable import DistrictData
import DistrictModel
import DistrictNetwork
import XCTest

final class SetupWizardRepositoryTests: XCTestCase {
    private static func json(_ body: String, _ status: Int = 200) -> HTTPResponse {
        HTTPResponse(statusCode: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }

    private static let state = json(
        #"{"setupProgress":{"steps":{"business":"done","number":"skipped","receptionist":"todo","#
            + #""callers":"todo","calls":"todo","golive":"todo"}},"businessFacts":null,"region":"us","#
            + #""tier":"Voice","includedNumbers":1,"numbersHeld":0}"#
    )

    private static let check = json(
        #"{"available":true,"forwardingCheck":{"id":"f1","status":"pending","mode":"all","#
            + #""businessLine":"+14165550123","startedAt":"2026-09-23T15:10:00.000Z","#
            + #""at":"2026-09-23T15:10:00.000Z","verifierNumber":"+14165550142","carrier":"twilio"},"#
            + #""attemptsLeft":4}"#,
        202
    )

    private static let ownerOnly = json(#"{"error":"Only the workspace owner can do this.","code":"forbidden"}"#, 403)

    func testEveryCallReachesItsRouteAndDecodesItsAnswer() async throws {
        let transport = RepositoryTransport([
            Self.state,
            Self.state,
            Self.json(
                #"{"draft":{"services":[{"name":"Cleaning","price":"$120","enabled":false}],"#
                    + #""faqs":[{"question":"Open late?","answer":"Thursdays.","enabled":false}],"dropped":0},"#
                    + #""source":{"kind":"website","url":"https://example.com/"}}"#
            ),
            Self.json(#"{"success":true,"callId":"CA1"}"#),
            Self.check,
            Self.check,
            Self.json(
                #"{"connections":[{"provider":"google-calendar","status":"active"}],"#
                    + #""calendar":{"activeProvider":"google","source":"preference"}}"#
            ),
        ])
        let repository = SetupWizardRepository(client: .repositoryTest(transport))
        let loaded = try await repository.load(workspaceId: "ws_1").get()
        let saved = try await repository.save(workspaceId: "ws_1", steps: [.number: .skipped]).get()
        let draft = try await repository.lookUp(workspaceId: "ws_1", websiteUrl: "example.com", locale: "en").get()
        let callId = try await repository.placeTestCall(workspaceId: "ws_1", phone: "+14165550123").get()
        let started = try await repository.startForwardingCheck(
            workspaceId: "ws_1",
            businessLine: "+14165550123",
            mode: .all
        ).get()
        let polled = try await repository.forwardingCheck(workspaceId: "ws_1").get()
        let connections = try await repository.connections(workspaceId: "ws_1").get()

        XCTAssertEqual(loaded.setupProgress?.steps?.state(of: .business), .done)
        XCTAssertEqual(saved.setupProgress?.steps?.state(of: .number), .skipped)
        XCTAssertEqual(saved.setupProgress?.steps?.state(of: .golive), .todo)
        XCTAssertEqual(draft.draft.services, [SetupDraftService(name: "Cleaning", price: "$120", enabled: false)])
        XCTAssertEqual(draft.draft.faqs, [SetupDraftFaq(question: "Open late?", answer: "Thursdays.", enabled: false)])
        XCTAssertNil(draft.draft.address)
        XCTAssertEqual(callId, "CA1")
        XCTAssertEqual(started.forwardingCheck?.isPending, true)
        XCTAssertEqual(polled.forwardingCheck?.hasPassed, false)
        XCTAssertEqual(polled.attemptsLeft, 4)
        XCTAssertTrue(connections.hasActiveCalendar)
        XCTAssertEqual(transport.requestedURLs.map { $0.components(separatedBy: "/api/").last }, [
            "district/setup?workspaceId=ws_1",
            "district/setup",
            "district/setup/lookup",
            "district/setup/test-call",
            "district/setup/forwarding-check",
            "district/setup/forwarding-check?workspaceId=ws_1",
            "district/connections?workspaceId=ws_1",
        ])
        XCTAssertEqual(transport.bodies, [
            #"{"setupProgress":{"steps":{"number":"skipped"}},"workspaceId":"ws_1"}"#,
            #"{"locale":"en","websiteUrl":"example.com","workspaceId":"ws_1"}"#,
            #"{"phone":"+14165550123","workspaceId":"ws_1"}"#,
            #"{"businessLine":"+14165550123","mode":"all","workspaceId":"ws_1"}"#,
        ])
    }

    /// ⛔ A SAVE WITH NOTHING IN IT SENDS NO `setupProgress` AND NO `businessFacts`, rather than
    /// an empty `steps` or a null that would clear a section.
    func testAnEmptySaveSendsOnlyTheWorkspace() async {
        let transport = RepositoryTransport([Self.state])
        _ = await SetupWizardRepository(client: .repositoryTest(transport)).save(workspaceId: "ws_1")
        XCTAssertEqual(transport.bodies, [#"{"workspaceId":"ws_1"}"#])
    }

    /// ⛔ OWNER ONLY: a member's 403 and a pre-wizard workspace's 409 keep their codes.
    func testRefusalsKeepTheServiceCode() async {
        let transport = RepositoryTransport([
            Self.ownerOnly,
            Self.json(
                #"{"error":"Guided setup is not available for this workspace.","code":"setup_not_available"}"#,
                409
            ),
            Self.json(
                #"{"error":"That website could not be read.","code":"website_unreadable","reason":"host_unavailable"}"#,
                422
            ),
            Self.json(#"{"error":"A test call is already in progress.","code":"test_call_in_progress"}"#, 409),
        ])
        let repository = SetupWizardRepository(client: .repositoryTest(transport))
        let member = await repository.load(workspaceId: "ws_1")
        let preWizard = await repository.save(workspaceId: "ws_1", steps: [.business: .done])
        let unreadable = await repository.lookUp(workspaceId: "ws_1", websiteUrl: "nowhere.invalid", locale: "fr")
        let busy = await repository.placeTestCall(workspaceId: "ws_1", phone: "+14165550123")
        XCTAssertEqual(member.failureOnly?.httpStatus, 403)
        XCTAssertEqual(preWizard.failureOnly?.code, "setup_not_available")
        XCTAssertEqual(unreadable.failureOnly?.code, "website_unreadable")
        XCTAssertEqual(busy.failureOnly?.code, "test_call_in_progress")
    }

    /// ⛔ A 200 THAT DOES NOT SAY THE CALL WAS PLACED IS NOT TAKEN AS PLACED.
    func testATestCallAnswerWithoutSuccessIsRefused() async {
        let transport = RepositoryTransport([Self.json(#"{"success":false,"callId":"CA1"}"#)])
        let outcome = await SetupWizardRepository(client: .repositoryTest(transport))
            .placeTestCall(workspaceId: "ws_1", phone: "+14165550123")
        XCTAssertEqual(outcome.failureOnly, .decoding("SetupTestCallResponse did not affirm success=true"))
    }

    /// A viewer's answer has no calendar resolution, and a step value this client does not
    /// know reads as no state rather than failing the decode.
    func testAViewerHasNoCalendarAndAnUnknownStepStateIsNil() async throws {
        let transport = RepositoryTransport([
            Self.json(#"{"connections":[]}"#),
            Self.json(
                #"{"setupProgress":{"steps":{"business":"paused"}},"businessFacts":null,"region":"us","#
                    + #""tier":null,"includedNumbers":null,"numbersHeld":null}"#
            ),
        ])
        let repository = SetupWizardRepository(client: .repositoryTest(transport))
        let viewer = try await repository.connections(workspaceId: "ws_1").get()
        let state = try await repository.load(workspaceId: "ws_1").get()
        XCTAssertNil(viewer.calendar)
        XCTAssertFalse(viewer.hasActiveCalendar)
        XCTAssertNil(state.setupProgress?.steps?.state(of: .business))
        XCTAssertNil(state.setupProgress?.steps?.state(of: .receptionist))
        XCTAssertNil(state.setupProgress?.steps?.state(of: .callers))
        XCTAssertNil(state.setupProgress?.steps?.state(of: .calls))
    }
}
