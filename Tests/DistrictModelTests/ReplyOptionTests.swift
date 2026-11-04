import DistrictModel
import XCTest

/// One `{channel, to}` pair from a conversation row's `replyOptions`, as a send destination.
final class ReplyOptionTests: XCTestCase {
    func testAKnownChannelWithAnAddressIsATarget() {
        XCTAssertEqual(
            ReplyOption(channel: MessageChannel.instagram, to: "ig:1").target,
            ReplyTarget(to: "ig:1", channel: MessageChannel.instagram)
        )
    }

    /// ⛔ NEVER A GUESS: an unknown channel, or a known one with no address, is no target.
    func testAnUnknownChannelOrABlankAddressIsNoTarget() {
        XCTAssertNil(ReplyOption(channel: "rcs", to: "+14165550100").target)
        XCTAssertNil(ReplyOption(channel: MessageChannel.sms, to: "  ").target)
    }

    func testTheReplyableChannelsAreTheFiveTheRouteSends() {
        XCTAssertEqual(MessageChannel.replyable, ["sms", "email", "whatsapp", "messenger", "instagram"])
    }
}
