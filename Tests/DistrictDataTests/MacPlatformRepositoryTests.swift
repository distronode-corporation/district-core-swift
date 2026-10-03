import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// The two repositories that carry a platform, built for the Mac.
///
/// ⚠️ THE iOS BYTES ARE PINNED BY `PushTokenRepositoryTests` AND `RoomsRepositoryTests`,
/// unchanged, through the ``ClientPlatform/ios`` default. These assert only that the
/// value given at construction reaches the wire.
final class MacPlatformRepositoryTests: XCTestCase {
    func testTheMacAlertRegisterSaysMacos() async {
        let transport = RepositoryTransport(json: #"{"success":true}"#)
        let memory = MacPushTokenMemory()

        let result = await PushTokenRepository(client: .repositoryTest(transport), memory: memory, platform: .macos)
            .register(token: "apns-token-1")

        XCTAssertEqual(result.successOnly, .registered)
        XCTAssertEqual(transport.bodies.first, #"{"platform":"macos","token":"apns-token-1"}"#)
        XCTAssertEqual(memory.lastRegisteredToken(), "apns-token-1")
    }

    func testTheMacRoomTokenIdentitySaysMacos() async throws {
        let transport = RepositoryTransport(json: RoomBodies.token())
        let room = try XCTUnwrap(RoomName(workspaceId: "ws-1", suffix: "standup"))

        let result = await RoomsRepository(client: .repositoryTest(transport), platform: .macos).token(roomName: room)

        XCTAssertEqual(result.successOnly?.token, "contract-livekit-room-jwt")
        XCTAssertEqual(transport.bodies.first, #"{"identity":"macos","roomName":"meet_ws-1_standup"}"#)
    }
}

private final class MacPushTokenMemory: PushTokenMemory, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    func lastRegisteredToken() -> String? {
        lock.withLock { token }
    }

    func rememberRegisteredToken(_ token: String) {
        lock.withLock { self.token = token }
    }

    func forgetRegisteredToken() {
        lock.withLock { token = nil }
    }

    /// ⚠️ A Mac never registers a VoIP token (the server refuses `macos` + `voip`),
    /// so these are never reached from this file.
    func lastRegisteredVoipToken() -> String? {
        nil
    }

    func rememberRegisteredVoipToken(_: String) {}

    func forgetRegisteredVoipToken() {}
}
