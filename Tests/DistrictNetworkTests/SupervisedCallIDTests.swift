@testable import DistrictNetwork
import Foundation
import XCTest

/// ⛔ THE MIRROR OF ``RoomNameTests``. `calls/token` reads its `roomName` by prefix: a
/// `meet_`/`video_` value is a standalone room (and `video_` a billable Tavus avatar), and
/// anything else a `Call.id` whose caller is stamped `supervisor`. The listen-in sends a
/// call id under that key, so a call id that looked like a room must not be expressible.
/// Since a uuid never carries `_` and every room name does, any underscore is refused.
final class SupervisedCallIDTests: XCTestCase {
    func testAServerCallIdIsAccepted() {
        let uuid = "3f2a9c1e-7b4d-4c1a-9e2f-0a1b2c3d4e5f"
        XCTAssertEqual(SupervisedCallID(uuid)?.value, uuid)
    }

    /// ⛔ BOTH PREFIXES THE ROUTE READS AS A ROOM, `video_` THE BILLABLE ONE.
    func testTheTwoRoomPrefixesAreRefused() {
        XCTAssertNil(SupervisedCallID("meet_x"))
        XCTAssertNil(SupervisedCallID("video_x"))
        XCTAssertNil(SupervisedCallID(RoomName.meetingPrefix + "ws1_demo"))
        XCTAssertNil(SupervisedCallID(RoomName.billableAvatarPrefix))
    }

    /// ⛔ ANY UNDERSCORE, ANYWHERE, matching core-rust's `LiveCallId`: every room family
    /// carries one and a uuid never does.
    func testAnyOtherUnderscoreIdIsRefused() {
        XCTAssertEqual(SupervisedCallID.separator, "_")
        for id in ["call_1", "direct_ws1_abc", "preview_x", "call-meet_1", "3f2a9c1e_7b4d", "_", "a_"] {
            XCTAssertNil(SupervisedCallID(id), id)
        }
    }

    func testABlankIdIsRefused() {
        XCTAssertNil(SupervisedCallID(""))
        XCTAssertNil(SupervisedCallID("  \n"))
    }

    func testTheMacListenIdentityIsMacos() throws {
        let descriptor = try DistrictEndpoints.monitorCall(callId: XCTUnwrap(SupervisedCallID("c1")), platform: .macos)
        guard case let .json(value) = descriptor.body else {
            return XCTFail("not a JSON body")
        }
        let encoded = try XCTUnwrap(String(data: JSONWire.encode(value), encoding: .utf8))
        XCTAssertEqual(encoded, #"{"identity":"macos","roomName":"c1"}"#)
    }

    /// ⛔ THE CALL ID IS ONE PATH SEGMENT: a `/` in it cannot address another route.
    func testATakeoverCallIdCannotTraverse() {
        let descriptor = DistrictEndpoints.takeOverCall(callId: "a/../answer", workspaceId: "ws_1")
        XCTAssertEqual(ApiPath.build(descriptor.segments), "/api/district/calls/a%2F..%2Fanswer/takeover")
    }
}
