@testable import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// App parity on the Inbox: the opt-in flags on the four reads, thread assignment, and the
/// WhatsApp composer's window, templates and sends.
///
/// ⛔ NO TEST HERE EXPECTS A SECOND REQUEST. Every write on this surface spends money or
/// pushes a person, and none is retried.
final class InboxParityRepositoryTests: XCTestCase {
    private static let host = "https://www.distronode.com/api/district"
    private static let unread = #"{"success":true,"count":4,"workspaceId":"ws_1"}"#
    private static let timeline = #"{"success":true,"timeline":[]}"#
    private static let thread = #"""
    {"success":true,"message":{"id":"msg_1","body":"Hi","direction":"inbound","type":"messenger",
     "readAt":null,"createdAt":"2026-08-15T14:30:00.000Z"},
     "thread":{"threadKey":"addr:fb:5550101","contactId":null,"counterpart":"fb:5550101",
     "channel":"messenger"}}
    """#

    private func everyRead(_ options: InboxReadOptions?) async -> [String] {
        let transport = RepositoryTransport(queue: [
            Bodies.conversations([]), Self.timeline, Self.unread, Self.thread,
        ])
        let client = ApiClient.repositoryTest(transport)
        let inbox = options.map { InboxRepository(client: client, options: $0) } ?? InboxRepository(client: client)
        _ = await inbox.conversations(workspaceId: "ws_1")
        _ = await inbox.timeline(workspaceId: "ws_1", selector: .contact("c_1"))
        _ = await inbox.unreadCount(workspaceId: "ws_1")
        _ = await inbox.messageThread(workspaceId: "ws_1", messageId: "msg_1")
        return transport.requestedURLs
    }

    // MARK: - The opt-in flags

    /// ⛔ THIS BUILD'S DEFAULT SENDS `metaChannels=1` ON ALL FOUR READS, so the list, the
    /// thread, the badge and the push resolver agree about Messenger and Instagram.
    func testTheDefaultAsksForMetaChannelsOnEveryRead() async {
        let urls = await everyRead(nil)

        XCTAssertEqual(urls, [
            "\(Self.host)/conversations?workspaceId=ws_1&metaChannels=1",
            "\(Self.host)/timeline?workspaceId=ws_1&contactId=c_1&metaChannels=1",
            "\(Self.host)/messages/unread-count?workspaceId=ws_1&metaChannels=1",
            "\(Self.host)/messages/msg_1?workspaceId=ws_1&metaChannels=1",
        ])
        XCTAssertEqual(InboxReadOptions(), InboxReadOptions(metaChannels: true, assignments: false))
    }

    /// ⛔ `legacy` IS BYTE FOR BYTE AN INSTALLED BUILD'S REQUESTS: the flags are dropped,
    /// never sent as `0`.
    func testLegacyOptionsSendNeitherFlag() async {
        let urls = await everyRead(.legacy)

        XCTAssertEqual(urls, [
            "\(Self.host)/conversations?workspaceId=ws_1",
            "\(Self.host)/timeline?workspaceId=ws_1&contactId=c_1",
            "\(Self.host)/messages/unread-count?workspaceId=ws_1",
            "\(Self.host)/messages/msg_1?workspaceId=ws_1",
        ])
    }

    /// ⚠️ `assignments=1` RIDES ON THE LIST ONLY, after `metaChannels`, and the rows decode
    /// with both new keys.
    func testAssignmentsAreAskedForOnTheListAndDecoded() async {
        let row = Bodies.conversation(threadKey: "contact:c_1")
            .replacingOccurrences(
                of: #""totalMessages":7}"#,
                with: #""totalMessages":7,"assigneeEmail":"a@b.test","assignedToMe":true}"#
            )
        let transport = RepositoryTransport(json: Bodies.conversations([row]))

        let result = await InboxRepository(
            client: .repositoryTest(transport),
            options: InboxReadOptions(metaChannels: true, assignments: true)
        ).conversations(workspaceId: "ws_1")

        XCTAssertEqual(
            transport.requestedURLs,
            ["\(Self.host)/conversations?workspaceId=ws_1&metaChannels=1&assignments=1"]
        )
        XCTAssertEqual(result.successOnly?.conversations.first?.assigneeEmail, "a@b.test")
        XCTAssertEqual(result.successOnly?.conversations.first?.assignedToMe, true)
    }

    /// ⚠️ THE META ROWS REACH THE THREAD AS THEIR OWN KINDS, not folded into SMS.
    func testTheTimelineKeepsMessengerAndInstagramRows() async {
        let transport = RepositoryTransport(json: #"""
        {"success":true,"timeline":[
         {"id":"m_1","type":"messenger","timestamp":"2026-08-15T14:30:00.000Z","direction":"inbound",
          "body":"Open Saturday?","status":"received"},
         {"id":"m_2","type":"instagram","timestamp":"2026-08-15T14:31:00.000Z","direction":"inbound",
          "body":"Price?","status":"received"}]}
        """#)

        let result = await InboxRepository(client: .repositoryTest(transport))
            .timeline(workspaceId: "ws_1", selector: .address("fb:5550101"))

        XCTAssertEqual(result.successOnly?.events.map(\.type), [ThreadEventKind.messenger, ThreadEventKind.instagram])
    }

    // MARK: - Thread assignment

    func testAssigningPostsTheThreadAndTheMember() async {
        let transport = RepositoryTransport(json: #"""
        {"success":true,"assignment":{"threadKey":"contact:c_1","assigneeEmail":"a@b.test",
         "assignedAt":"2026-10-29T12:00:00.000Z"}}
        """#)

        let result = await InboxRepository(client: .repositoryTest(transport))
            .assign(workspaceId: "ws_1", threadKey: "contact:c_1", assigneeEmail: "a@b.test")

        XCTAssertEqual(result.successOnly??.assigneeEmail, "a@b.test")
        XCTAssertEqual(transport.requests.first?.method, .post)
        XCTAssertEqual(transport.requestedURLs, ["\(Self.host)/conversations/assign"])
        XCTAssertEqual(
            transport.bodies,
            [#"{"assigneeEmail":"a@b.test","threadKey":"contact:c_1","workspaceId":"ws_1"}"#]
        )
    }

    /// ⛔ THE UNASSIGN SENDS AN EXPLICIT NULL. An absent key is a 400 `validation_failed`.
    func testUnassigningSendsAnExplicitNullAndAnswersNil() async {
        let transport = RepositoryTransport(json: #"{"success":true,"assignment":null}"#)

        let result = await InboxRepository(client: .repositoryTest(transport))
            .assign(workspaceId: "ws_1", threadKey: "contact:c_1", assigneeEmail: nil)

        XCTAssertEqual(result.successOnly.map { $0 == nil }, true)
        XCTAssertEqual(
            transport.bodies,
            [#"{"assigneeEmail":null,"threadKey":"contact:c_1","workspaceId":"ws_1"}"#]
        )
    }

    /// ⚠️ THE VIEWER REFUSAL KEEPS ITS CODE, so the screen can say it in either language.
    func testAViewerAssigneeIsOneCodedRefusal() async {
        let transport = RepositoryTransport(
            json: #"{"success":false,"error":"A Viewer cannot be assigned.","code":"assignee_is_viewer"}"#,
            status: 400
        )

        let result = await InboxRepository(client: .repositoryTest(transport))
            .assign(workspaceId: "ws_1", threadKey: "contact:c_1", assigneeEmail: "v@b.test")

        XCTAssertEqual(result.failureOnly?.code, ApiErrorCode.assigneeIsViewer)
        XCTAssertEqual(result.failureOnly?.httpStatus, 400)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testAnAssignmentThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport(json: #"{"success":false,"assignment":null}"#)

        let result = await InboxRepository(client: .repositoryTest(transport))
            .assign(workspaceId: "ws_1", threadKey: "contact:c_1", assigneeEmail: nil)

        XCTAssertEqual(result.failureOnly, .decoding("ConversationAssignResponse did not affirm success=true"))
    }

    // MARK: - WhatsApp

    func testTheWindowReadSendsTheCustomerAndOptionallyTheSender() async {
        let body = #"""
        {"success":true,"window":{"open":true,"expiresAt":"2026-08-16T14:25:00.000Z"},
         "senderId":"wa_1","receivedOn":"+16475550100"}
        """#
        let transport = RepositoryTransport(queue: [body, body])
        let inbox = InboxRepository(client: .repositoryTest(transport))

        let result = await inbox.whatsAppWindow(workspaceId: "ws_1", to: "+14165550177")
        _ = await inbox.whatsAppWindow(workspaceId: "ws_1", to: "+14165550177", senderId: "wa_2")

        XCTAssertEqual(result.successOnly?.window.open, true)
        XCTAssertEqual(result.successOnly?.window.expiresAt, "2026-08-16T14:25:00.000Z")
        XCTAssertEqual(result.successOnly?.senderId, "wa_1")
        XCTAssertEqual(transport.requestedURLs, [
            "\(Self.host)/workspace/whatsapp/window?workspaceId=ws_1&to=%2B14165550177",
            "\(Self.host)/workspace/whatsapp/window?workspaceId=ws_1&to=%2B14165550177&senderId=wa_2",
        ])
    }

    func testAWindowThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport(
            json: #"{"success":false,"window":{"open":false},"senderId":"wa_1"}"#
        )

        let result = await InboxRepository(client: .repositoryTest(transport))
            .whatsAppWindow(workspaceId: "ws_1", to: "+14165550177")

        XCTAssertEqual(result.failureOnly, .decoding("WhatsAppWindowResponse did not affirm success=true"))
    }

    func testTheTemplatesReadNamesTheSender() async {
        let transport = RepositoryTransport(json: #"""
        {"success":true,"templates":[{"id":"t_1","name":"reminder","language":"en_US",
         "category":"UTILITY","status":"approved","body":"Hi {{1}}","variableCount":1}]}
        """#)

        let result = await InboxRepository(client: .repositoryTest(transport))
            .whatsAppTemplates(workspaceId: "ws_1", senderId: "wa_1")

        XCTAssertEqual(result.successOnly?.map(\.id), ["t_1"])
        XCTAssertEqual(result.successOnly?.first?.isSendable, true)
        XCTAssertEqual(
            transport.requestedURLs,
            ["\(Self.host)/workspace/whatsapp/templates?workspaceId=ws_1&senderId=wa_1"]
        )
    }

    func testATemplatesListThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport(json: #"{"success":false,"templates":[]}"#)

        let result = await InboxRepository(client: .repositoryTest(transport))
            .whatsAppTemplates(workspaceId: "ws_1", senderId: "wa_1")

        XCTAssertEqual(result.failureOnly, .decoding("WhatsAppTemplatesResponse did not affirm success=true"))
    }

    /// ⛔ THE TEMPLATE SEND IS A BODY ON `messages/send`, with the preview as `body`, and
    /// the answer's body is the server's fill.
    func testATemplateSendPostsTheTemplateAndItsVariables() async throws {
        let transport = RepositoryTransport(json: Self.sent(body: "Hi Ada, see you Thursday."))
        let template = try Self.template(#"{"body":"Hi {{1}}, see you {{2}}.","variableCount":2}"#)

        let result = await InboxRepository(client: .repositoryTest(transport)).sendWhatsAppTemplate(
            workspaceId: "ws_1",
            to: "+14165550177",
            senderId: "wa_1",
            template: template,
            variables: ["Ada", "Thursday"]
        )

        XCTAssertEqual(result.successOnly?.body, "Hi Ada, see you Thursday.")
        XCTAssertEqual(transport.requestedURLs, ["\(Self.host)/messages/send"])
        XCTAssertEqual(transport.bodies, [
            #"{"body":"Hi Ada, see you Thursday.","channel":"whatsapp","templateId":"t_1","#
                + #""templateVariables":["Ada","Thursday"],"to":"+14165550177","whatsappSenderId":"wa_1","#
                + #""workspaceId":"ws_1"}"#,
        ])
    }

    func testATemplateSendThatDoesNotAffirmSuccessIsADecodeFailure() async throws {
        let transport = RepositoryTransport(json: Self.sent(body: "x").replacingOccurrences(
            of: #""success":true"#, with: #""success":false"#
        ))
        let template = try Self.template(#"{"body":"x","variableCount":0}"#)

        let result = await InboxRepository(client: .repositoryTest(transport)).sendWhatsAppTemplate(
            workspaceId: "ws_1", to: "+1", senderId: nil, template: template, variables: []
        )

        XCTAssertEqual(result.failureOnly, .decoding("SendMessageResponse did not affirm success=true"))
    }

    /// ⚠️ A FREE-FORM WHATSAPP SEND NAMES ITS SENDER WHEN GIVEN ONE, and drops the key when
    /// not, so the server picks the number the customer wrote to.
    func testAFreeFormWhatsAppSendNamesTheSenderOnlyWhenGiven() async {
        let transport = RepositoryTransport(queue: [Self.sent(body: "On my way."), Self.sent(body: "On my way.")])
        let inbox = InboxRepository(client: .repositoryTest(transport))

        let named = await inbox.sendWhatsApp(
            workspaceId: "ws_1",
            to: "+14165550177",
            body: "On my way.",
            senderId: "wa_1"
        )
        _ = await inbox.sendWhatsApp(workspaceId: "ws_1", to: "+14165550177", body: "On my way.", senderId: nil)

        XCTAssertEqual(named.successOnly?.type, MessageChannel.whatsapp)
        XCTAssertEqual(transport.bodies, [
            #"{"body":"On my way.","channel":"whatsapp","to":"+14165550177","#
                + #""whatsappSenderId":"wa_1","workspaceId":"ws_1"}"#,
            #"{"body":"On my way.","channel":"whatsapp","to":"+14165550177","workspaceId":"ws_1"}"#,
        ])
    }

    func testAFreeFormWhatsAppSendThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport(json: Self.sent(body: "x").replacingOccurrences(
            of: #""success":true"#, with: #""success":false"#
        ))

        let result = await InboxRepository(client: .repositoryTest(transport))
            .sendWhatsApp(workspaceId: "ws_1", to: "+1", body: "x", senderId: nil)

        XCTAssertEqual(result.failureOnly, .decoding("SendMessageResponse did not affirm success=true"))
    }

    /// ⛔ A CLOSED WINDOW AT SEND TIME IS ONE CODED REFUSAL, NOT A RETRY.
    func testAClosedWindowAtSendTimeIsOneRefusal() async {
        let transport = RepositoryTransport(
            json: #"{"success":false,"error":"The window is closed.","code":"whatsapp_window_closed"}"#,
            status: 409
        )

        let result = await InboxRepository(client: .repositoryTest(transport))
            .sendWhatsApp(workspaceId: "ws_1", to: "+14165550177", body: "Hi", senderId: nil)

        XCTAssertEqual(result.failureOnly?.code, "whatsapp_window_closed")
        XCTAssertEqual(transport.requests.count, 1)
    }

    /// A template decoded from bytes, as the picker gets one. ⚠️ Not built with a memberwise
    /// initialiser: that is internal to `DistrictModel`, like every DTO's.
    private static func template(_ fields: String) throws -> WhatsAppTemplate {
        let base = #"{"id":"t_1","name":"reminder","language":"en_US","category":"UTILITY","status":"approved","#
        return try JSONDecoder().decode(WhatsAppTemplate.self, from: Data((base + fields.dropFirst()).utf8))
    }

    private static func sent(body: String) -> String {
        #"""
        {"success":true,"message":{"id":"m_1","messageSid":"wamid.1","workspaceId":"ws_1",
         "from":"+16475550100","to":"+14165550177","body":"\#(body)","direction":"outbound",
         "type":"whatsapp","status":"sent","createdAt":"2026-08-15T14:30:00.000Z",
         "externalId":"wamid.1","provider":"meta","accountId":"wa_1"}}
        """#
    }

    // MARK: - Messenger and Instagram

    func testTheMetaWindowReadSendsTheChannelAndTheAddress() async {
        let transport = RepositoryTransport(queue: [
            #"{"success":true,"window":{"state":"human_agent","until":"2026-08-22T14:25:00.000Z"}}"#,
            #"{"success":true,"window":{"state":"closed","until":null}}"#,
        ])
        let inbox = InboxRepository(client: .repositoryTest(transport))

        let messenger = await inbox.metaWindow(workspaceId: "ws_1", channel: MessageChannel.messenger, to: "fb:5550101")
        let instagram = await inbox.metaWindow(workspaceId: "ws_1", channel: MessageChannel.instagram, to: "ig:5550102")

        XCTAssertEqual(messenger.successOnly, MetaWindow(state: .humanAgent, until: "2026-08-22T14:25:00.000Z"))
        XCTAssertEqual(instagram.successOnly, MetaWindow(state: .closed, until: nil))
        XCTAssertEqual(transport.requestedURLs, [
            "\(Self.host)/messages/send?workspaceId=ws_1&channel=messenger&to=fb%3A5550101",
            "\(Self.host)/messages/send?workspaceId=ws_1&channel=instagram&to=ig%3A5550102",
        ])
    }

    func testAMetaWindowThatDoesNotAffirmSuccessIsADecodeFailure() async {
        let transport = RepositoryTransport(json: #"{"success":false,"window":{"state":"open","until":null}}"#)

        let result = await InboxRepository(client: .repositoryTest(transport))
            .metaWindow(workspaceId: "ws_1", channel: MessageChannel.messenger, to: "fb:5550101")

        XCTAssertEqual(result.failureOnly, .decoding("MetaWindowResponse did not affirm success=true"))
    }
}
