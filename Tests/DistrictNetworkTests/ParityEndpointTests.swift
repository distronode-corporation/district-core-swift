import DistrictModel
@testable import DistrictNetwork
import Foundation
import XCTest

/// App parity's new queries and bodies on EXISTING endpoint ids, which `EndpointTable`
/// cannot hold (one row per id): the opt-in flags on the four Inbox reads, the push
/// registration's `capabilities`, the unassign's explicit null, and the two WhatsApp sends
/// on `messages/send`.
///
/// ⛔ EVERY "OFF" CASE IS ASSERTED BYTE FOR BYTE AGAINST THE OLD DESCRIPTOR. The server's
/// compatibility story is that a read without the flags answers what installed builds
/// decode, so a `metaChannels=0` or an empty `capabilities` key would be a change no
/// fixture catches.
final class ParityEndpointTests: XCTestCase {
    private let base = URL(string: EndpointTable.host)!

    private func url(_ descriptor: ApiRequestDescriptor) -> String? {
        ApiURL.build(base: base, segments: descriptor.segments, query: descriptor.query)?.absoluteString
    }

    private func body(_ descriptor: ApiRequestDescriptor) throws -> String {
        guard case let .json(value) = descriptor.body else {
            XCTFail("expected a JSON body")
            return ""
        }
        return try XCTUnwrap(String(data: JSONWire.encode(value), encoding: .utf8))
    }

    // MARK: - The Inbox reads

    func testEveryReadCarriesTheFlagsWhenOnAndNothingWhenOff() {
        let host = "\(EndpointTable.host)/api/district"
        let both = InboxReadOptions(metaChannels: true, assignments: true)

        XCTAssertEqual(
            url(DistrictEndpoints.conversations(workspaceId: "ws_1", options: both)),
            "\(host)/conversations?workspaceId=ws_1&metaChannels=1&assignments=1"
        )
        XCTAssertEqual(
            url(DistrictEndpoints.conversations(workspaceId: "ws_1", options: .legacy)),
            url(DistrictEndpoints.conversations(workspaceId: "ws_1"))
        )
        XCTAssertEqual(
            url(DistrictEndpoints.timeline(
                workspaceId: "ws_1", contactId: nil, address: "+1416", before: "t", beforeId: "m", metaChannels: true
            )),
            "\(host)/timeline?workspaceId=ws_1&phoneNumber=%2B1416&before=t&beforeId=m&metaChannels=1"
        )
        XCTAssertEqual(
            url(DistrictEndpoints.timeline(workspaceId: "ws_1", contactId: "c_1", address: nil, metaChannels: false)),
            url(DistrictEndpoints.timeline(workspaceId: "ws_1", contactId: "c_1", address: nil))
        )
        XCTAssertEqual(
            url(DistrictEndpoints.unreadCount(workspaceId: "ws_1", metaChannels: true)),
            "\(host)/messages/unread-count?workspaceId=ws_1&metaChannels=1"
        )
        XCTAssertEqual(
            url(DistrictEndpoints.unreadCount(workspaceId: "ws_1", metaChannels: false)),
            url(DistrictEndpoints.unreadCount(workspaceId: "ws_1"))
        )
        XCTAssertEqual(
            url(DistrictEndpoints.messageThread(workspaceId: "ws_1", id: "msg_1", metaChannels: true)),
            "\(host)/messages/msg_1?workspaceId=ws_1&metaChannels=1"
        )
        XCTAssertEqual(
            url(DistrictEndpoints.messageThread(workspaceId: "ws_1", id: "msg_1", metaChannels: false)),
            url(DistrictEndpoints.messageThread(workspaceId: "ws_1", id: "msg_1"))
        )
    }

    /// The ids stay the old ones: these are the same routes.
    func testTheFlaggedReadsKeepTheirEndpointIds() {
        XCTAssertEqual(DistrictEndpoints.conversations(workspaceId: "w", options: .init()).id, .conversations)
        XCTAssertEqual(DistrictEndpoints.unreadCount(workspaceId: "w", metaChannels: true).id, .unreadCount)
        XCTAssertEqual(
            DistrictEndpoints.timeline(workspaceId: "w", contactId: "c", address: nil, metaChannels: true).id,
            .timeline
        )
        XCTAssertEqual(
            DistrictEndpoints.messageThread(workspaceId: "w", id: "m", metaChannels: true).id,
            .messageThread
        )
    }

    // MARK: - Assignment

    /// ⛔ AN ABSENT KEY IS A 400; THE UNASSIGN MUST SEND `null`.
    func testTheUnassignSendsAnExplicitNull() throws {
        let descriptor = DistrictEndpoints.assignConversation(
            workspaceId: "ws_1",
            threadKey: "addr:1",
            assigneeEmail: nil
        )

        XCTAssertEqual(try body(descriptor), #"{"assigneeEmail":null,"threadKey":"addr:1","workspaceId":"ws_1"}"#)
    }

    // MARK: - Push registration

    func testCapabilitiesAreSortedAndAnEmptySetIsTheOldBody() throws {
        let declared = DistrictEndpoints.registerPushToken(
            token: "t",
            capabilities: [.metaChannels, DeviceCapability(rawValue: "aFutureOne")]
        )
        let none = DistrictEndpoints.registerPushToken(token: "t", platform: .macos, capabilities: [])

        XCTAssertEqual(declared.id, .registerPushToken)
        XCTAssertEqual(
            try body(declared),
            #"{"capabilities":["aFutureOne","metaChannels"],"platform":"ios","token":"t"}"#
        )
        XCTAssertEqual(try body(none), try body(DistrictEndpoints.registerPushToken(token: "t", platform: .macos)))
        XCTAssertEqual(DeviceCapability.metaChannels.rawValue, "metaChannels")
    }

    // MARK: - WhatsApp sends

    /// ⛔ BOTH ARE `messages/send`, so the same id and the same path as every reply.
    func testTheWhatsAppSendsAreBodiesOnMessagesSend() throws {
        let picked = try JSONDecoder().decode(WhatsAppTemplate.self, from: Data(#"""
        {"id":"t_1","senderId":null,"name":"hello","language":"en_US","category":"UTILITY",
         "status":"approved","body":"Hi {{1}}","variableCount":1}
        """#.utf8))
        let template = DistrictEndpoints.sendWhatsAppTemplate(
            workspaceId: "ws_1", to: "+1416", senderId: nil, template: picked, variables: ["Ada"]
        )
        let text = DistrictEndpoints.sendWhatsApp(workspaceId: "ws_1", to: "+1416", body: "Hi", senderId: "wa_1")

        for descriptor in [template, text] {
            XCTAssertEqual(descriptor.id, .sendMessage)
            XCTAssertEqual(descriptor.method, .post)
            XCTAssertEqual(url(descriptor), "\(EndpointTable.host)/api/district/messages/send")
        }
        XCTAssertEqual(
            try body(template),
            #"{"body":"Hi Ada","channel":"whatsapp","templateId":"t_1","templateVariables":["Ada"],"#
                + #""to":"+1416","workspaceId":"ws_1"}"#
        )
        XCTAssertEqual(
            try body(text),
            #"{"body":"Hi","channel":"whatsapp","to":"+1416","whatsappSenderId":"wa_1","workspaceId":"ws_1"}"#
        )
    }

    func testTheWindowReadDropsAnAbsentSender() {
        XCTAssertEqual(
            url(DistrictEndpoints.whatsAppWindow(workspaceId: "ws_1", to: "+1416", senderId: "wa_1")),
            "\(EndpointTable.host)/api/district/workspace/whatsapp/window?workspaceId=ws_1&to=%2B1416&senderId=wa_1"
        )
    }
}
