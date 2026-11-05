import ContractGateSupport
import DistrictL10n
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// Per-fixture assertions for app parity: the Inbox's reply options and assignment, the
/// timeline's Meta rows, and the WhatsApp window, templates and template send.
///
/// ⚠️ THE STRICT GATE PROVES THE KEY SETS (decode, re-encode, compare); THESE PROVE WHAT A
/// SCREEN READS OFF THEM. The reply path is the one that matters: the server's
/// `replyOptions` replaces this client's `canSms`/`canEmail` routing whenever it is sent.
final class ParityContractTests: XCTestCase {
    private func replyOptions() throws -> ConversationsResponse {
        try StrictDecodeVerifier.verify(
            fixture: "district-conversations-reply-options.json",
            as: ConversationsResponse.self
        )
    }

    // MARK: - Reply options

    /// ⛔ EVERY ROW REPLIES ON THE SERVER'S FIRST OPTION, and the Meta threads on their own
    /// channel with their `fb:`/`ig:` address, never by SMS.
    func testEachRowRepliesOnTheServersFirstOption() throws {
        let rows = try replyOptions().conversations

        XCTAssertEqual(rows.map(\.replyTarget), [
            ReplyTarget(to: "+14165550177", channel: MessageChannel.whatsapp),
            ReplyTarget(to: "fb:5550101", channel: MessageChannel.messenger),
            ReplyTarget(to: "ig:5550102", channel: MessageChannel.instagram),
            ReplyTarget(to: "ada@contract.test", channel: MessageChannel.email),
            ReplyTarget(to: "+14165558888", channel: MessageChannel.sms),
        ])
        // ⛔ THE WHATSAPP-ONLY ROW STILL SAYS `canSms: true`. Read alone, that is the bug
        // `replyOptions` closes: the customer would have been texted.
        XCTAssertTrue(rows[0].canSms)
        XCTAssertFalse(rows[1].canSms)
        XCTAssertNil(rows[0].assigneeEmail)
        XCTAssertNil(rows[0].assignedToMe, "assignments=1 was not asked for")
    }

    /// The folded thread offers all three channels in the server's order.
    func testTheFoldedThreadOffersEveryChannelInTheServersOrder() throws {
        let folded = try replyOptions().conversations[3]

        XCTAssertEqual(folded.replyTargets.map(\.channel), [
            MessageChannel.email, MessageChannel.sms, MessageChannel.whatsapp,
        ])
        XCTAssertEqual(folded.replyTargets.map(\.to), ["ada@contract.test", "14165551234", "+14165551234"])
    }

    /// The reply-options fixture with each row's `replyOptions` rewritten, decoded the way
    /// the repository decodes it.
    ///
    /// ⚠️ EDITED AS A DOCUMENT, NOT AS TEXT, so a change to the fixture's whitespace cannot
    /// turn a replacement into a silent no-op.
    private func editedRows(_ edit: (inout [[String: Any]]) -> Void) throws -> [ConversationSummary] {
        let data = try ContractFixtures.read("district-conversations-reply-options.json")
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var rows = try XCTUnwrap(document["conversations"] as? [[String: Any]])
        edit(&rows)
        document["conversations"] = rows
        let edited = try JSONSerialization.data(withJSONObject: document)
        return try JSONDecoder().decode(ConversationsResponse.self, from: edited).conversations
    }

    /// ⛔ A CHANNEL THIS BUILD DOES NOT KNOW DECODES AND IS SKIPPED, never a decode failure:
    /// the Instagram row's only option renamed to an unknown channel leaves it with no reply
    /// box, and an unknown option ahead of the folded thread's first is passed over.
    func testAnUnknownChannelDecodesAndIsSkipped() throws {
        let rows = try editedRows { rows in
            rows[2]["replyOptions"] = [["channel": "carrier-pigeon", "to": "ig:5550102"]]
            let folded = rows[3]["replyOptions"] as? [[String: String]] ?? []
            rows[3]["replyOptions"] = [["channel": "rcs", "to": "x"]] + folded
        }

        XCTAssertEqual(rows[2].replyOptions?.map(\.channel), ["carrier-pigeon"])
        XCTAssertNil(rows[2].replyTarget, "an unknown channel is no reply box, not a guess")
        XCTAssertEqual(rows[3].replyOptions?.first?.channel, "rcs")
        XCTAssertEqual(rows[3].replyTarget?.channel, MessageChannel.email)
        XCTAssertEqual(rows[3].replyTargets.count, 3)
    }

    /// ⛔ `[]` IS AN ANSWER: no reply box, and NOT a fall back to `canSms`.
    func testAnEmptyOptionListIsNoReplyBox() throws {
        let stranger = try editedRows { rows in rows[4]["replyOptions"] = [Any]() }[4]

        XCTAssertTrue(stranger.canSms)
        XCTAssertEqual(stranger.replyOptions, [])
        XCTAssertNil(stranger.replyTarget)
    }

    // MARK: - Assignment

    func testAssignmentsSayWhoOwnsEachThread() throws {
        let rows = try StrictDecodeVerifier.verify(
            fixture: "district-conversations-assignee.json",
            as: ConversationsResponse.self
        ).conversations

        XCTAssertEqual(rows[0].assigneeEmail, "contract@distronode.test")
        XCTAssertEqual(rows[0].assignedToMe, true)
        XCTAssertNil(rows[1].assigneeEmail)
        XCTAssertEqual(rows[1].assignedToMe, false, "asked for, and unassigned")
        // Without `metaChannels=1` the legacy routing still answers.
        XCTAssertNil(rows[0].replyOptions)
        XCTAssertEqual(rows[0].replyTarget?.channel, MessageChannel.sms)
    }

    func testAnAssignAnswersTheStoredRowAndAnUnassignAnswersNil() throws {
        let assigned = try StrictDecodeVerifier.verify(
            fixture: "district-conversation-assign.json",
            as: ConversationAssignResponse.self
        )
        let unassigned = try StrictDecodeVerifier.verify(
            fixture: "district-conversation-unassign.json",
            as: ConversationAssignResponse.self
        )

        XCTAssertEqual(assigned.assignment?.threadKey, "contact:contact_contract_1")
        XCTAssertEqual(assigned.assignment?.assigneeEmail, "teammate@contract.test")
        XCTAssertEqual(assigned.assignment?.assignedAt, "2026-10-29T12:00:00.000Z")
        XCTAssertTrue(unassigned.success)
        XCTAssertNil(unassigned.assignment)
    }

    /// ⛔ THE VIEWER REFUSAL REACHES A SCREEN THROUGH THE ERROR TABLE: its code survives the
    /// normaliser, and in French the sentence is the catalog's, never the English wire text.
    func testTheViewerRefusalMapsThroughTheErrorTable() throws {
        let envelope = try StrictDecodeVerifier.verify(
            fixture: "district-conversation-assign-viewer.json",
            as: ApiErrorEnvelope.self
        )
        XCTAssertEqual(envelope.code, ApiErrorCode.assigneeIsViewer)

        let error = try ApiErrorNormalizer.apiError(
            statusCode: 400,
            body: ContractFixtures.read("district-conversation-assign-viewer.json")
        )

        XCTAssertEqual(error.code, "assignee_is_viewer")
        XCTAssertEqual(error.httpStatus, 400)
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(error.localizedMessage, ApiErrorText.sentence(for: ApiErrorCode.assigneeIsViewer))
            XCTAssertNotEqual(error.localizedMessage, envelope.error)
        }
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(error.localizedMessage, envelope.error)
        }
    }

    /// The stopgap's 409, as the route writes it (no fixture: the body is the plain envelope).
    func testTheSmsStopgapMapsThroughTheErrorTable() {
        let body = #"{"success":false,"error":"Reply on their channel.","code":"sms_reply_not_customer_channel"}"#

        let error = ApiErrorNormalizer.apiError(statusCode: 409, body: Data(body.utf8))

        XCTAssertEqual(error.code, ApiErrorCode.smsReplyNotCustomerChannel)
        XCTAssertEqual(error.httpStatus, 409)
        L10nRuntime.withLocale(.frCA) {
            let french = ApiErrorText.sentence(for: ApiErrorCode.smsReplyNotCustomerChannel)
            XCTAssertNotNil(french)
            XCTAssertEqual(error.localizedMessage, french)
        }
        XCTAssertNotNil(ApiErrorText.sentence(for: ApiErrorCode.assigneeNotMember))
    }

    // MARK: - The timeline

    func testTheTimelineCarriesAMessengerRowAsARawType() throws {
        let response = try StrictDecodeVerifier.verify(
            fixture: "district-timeline-meta.json",
            as: TimelineResponse.self
        )

        XCTAssertEqual(response.timeline.last?.type, MessageChannel.messenger)
        XCTAssertEqual(response.timeline.last?.body, "Are you open Saturday?")
        XCTAssertEqual(response.timeline.count, 6)
    }

    // MARK: - WhatsApp

    func testTheWindowOpenAndClosed() throws {
        let open = try StrictDecodeVerifier.verify(
            fixture: "district-whatsapp-window.json",
            as: WhatsAppWindowResponse.self
        )
        let closed = try StrictDecodeVerifier.verify(
            fixture: "district-whatsapp-window-closed.json",
            as: WhatsAppWindowResponse.self
        )

        XCTAssertTrue(open.window.open)
        XCTAssertEqual(open.window.expiresAt, "2026-08-16T14:25:00.000Z")
        XCTAssertEqual(open.receivedOn, "+16475550100")
        XCTAssertFalse(closed.window.open)
        XCTAssertNil(closed.window.expiresAt)
        XCTAssertNil(closed.receivedOn)
        XCTAssertEqual(closed.senderId, "wa_sender_contract", "the sender is named even when closed")
    }

    /// ⚠️ ONLY THE APPROVED TEMPLATE IS SENDABLE; the pending one is listed, not offered.
    func testOnlyAnApprovedTemplateIsSendable() throws {
        let templates = try StrictDecodeVerifier.verify(
            fixture: "district-whatsapp-templates.json",
            as: WhatsAppTemplatesResponse.self
        ).templates

        XCTAssertEqual(templates.map(\.isSendable), [true, false])
        XCTAssertEqual(templates[0].variableCount, 2)
        XCTAssertNil(templates[0].senderId)
        XCTAssertNil(templates[1].variableCount, "named placeholders")
        XCTAssertEqual(templates[1].senderId, "wa_sender_contract")
    }

    /// The composer's preview: numbered placeholders filled in order, named ones left alone,
    /// and a body that fills to nothing falls back to the name (the route refuses an empty
    /// body).
    func testATemplateFillsItsNumberedPlaceholders() throws {
        let templates = try StrictDecodeVerifier.verify(
            fixture: "district-whatsapp-templates.json",
            as: WhatsAppTemplatesResponse.self
        ).templates

        XCTAssertEqual(
            templates[0].filled(with: ["Ada", "Thursday"]),
            "Hi Ada, this is a reminder of your appointment on Thursday."
        )
        XCTAssertEqual(templates[1].filled(with: ["Ada"]), "Bonjour {{first_name}}, merci de votre visite.")

        let blank = try JSONDecoder().decode(WhatsAppTemplate.self, from: Data(#"""
        {"id":"t","name":"hello_world","language":"en_US","category":"UTILITY","status":"approved","body":""}
        """#.utf8))
        XCTAssertEqual(blank.filled(with: []), "hello_world")
    }

    /// The template send echoes the usual row, with the SERVER's fill as the body.
    func testATemplateSendEchoesTheFilledBody() throws {
        let sent = try StrictDecodeVerifier.verify(
            fixture: "district-message-send-whatsapp-template.json",
            as: SendMessageResponse.self
        ).message

        XCTAssertEqual(sent.type, MessageChannel.whatsapp)
        XCTAssertEqual(sent.provider, "meta")
        XCTAssertEqual(sent.body, "Hi Ada, this is a reminder of your appointment on Thursday.")
        XCTAssertNil(sent.subject)
    }
}
