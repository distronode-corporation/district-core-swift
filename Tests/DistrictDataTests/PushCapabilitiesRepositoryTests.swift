import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// The push registration's `capabilities`: what this installation declares it can open.
///
/// ⛔ THE UPGRADE IS THE CASE THAT MATTERS. An app update does not rotate the APNs token,
/// so a skip keyed on the token alone would never send the register that declares
/// `metaChannels`, and Messenger and Instagram pushes would never reach the build that can
/// open them.
final class PushCapabilitiesRepositoryTests: XCTestCase {
    private static let ok = #"{"success":true}"#

    private func repository(
        _ transport: RepositoryTransport,
        _ memory: any PushTokenMemory,
        _ capabilities: Set<DeviceCapability> = [.metaChannels]
    ) -> PushTokenRepository {
        PushTokenRepository(
            client: .repositoryTest(transport),
            memory: memory,
            platform: .ios,
            capabilities: capabilities
        )
    }

    func testTheAlertRegisterDeclaresTheCapabilitiesAndRemembersThem() async {
        let memory = CapabilityMemory()
        let transport = RepositoryTransport(json: Self.ok)

        let result = await repository(transport, memory).register(token: "apns-1")

        XCTAssertEqual(result.successOnly, .registered)
        XCTAssertEqual(transport.bodies, [#"{"capabilities":["metaChannels"],"platform":"ios","token":"apns-1"}"#])
        XCTAssertEqual(memory.lastRegisteredCapabilities(), "metaChannels")
    }

    /// ⛔ THE UPGRADE: the same token, remembered with no capabilities, is sent again once.
    func testAnUnchangedTokenIsSentAgainWhenTheCapabilitiesChanged() async {
        let memory = CapabilityMemory(token: "apns-1")
        let transport = RepositoryTransport(queue: [Self.ok, Self.ok])
        let push = repository(transport, memory)

        let first = await push.register(token: "apns-1")
        let second = await push.register(token: "apns-1")

        XCTAssertEqual(first.successOnly, .registered)
        XCTAssertEqual(second.successOnly, .alreadyRegistered)
        XCTAssertEqual(transport.requests.count, 1)
    }

    /// ⚠️ A MEMORY THAT DOES NOT STORE CAPABILITIES (the protocol's defaults) NEVER SKIPS A
    /// DECLARING REGISTER: one request per register, never a declaration lost.
    func testAMemoryWithoutCapabilityStorageNeverSkipsADeclaringRegister() async {
        let memory = TokenOnlyMemory(token: "apns-1")
        let transport = RepositoryTransport(json: Self.ok)

        let result = await repository(transport, memory).register(token: "apns-1")

        XCTAssertEqual(result.successOnly, .registered)
        XCTAssertNil(memory.lastRegisteredCapabilities())
        XCTAssertEqual(transport.requests.count, 1)
    }

    /// ⛔ DECLARING NOTHING IS BYTE FOR BYTE THE OLD REGISTER, and its skip is the old skip
    /// even against a memory that stores nothing for capabilities.
    func testDeclaringNothingSendsNoKeyAndSkipsAsBefore() async {
        let transport = RepositoryTransport(queue: [Self.ok])
        let push = repository(transport, TokenOnlyMemory(), [])

        _ = await push.register(token: "apns-1")
        let again = await push.register(token: "apns-1")

        XCTAssertEqual(transport.bodies, [#"{"platform":"ios","token":"apns-1"}"#])
        XCTAssertEqual(again.successOnly, .alreadyRegistered)
    }

    /// ⚠️ THE VOIP TOKEN NEVER CARRIES THEM: a ring is not a message push.
    func testTheVoipRegisterDeclaresNothing() async {
        let memory = CapabilityMemory()
        let transport = RepositoryTransport(json: Self.ok)

        _ = await repository(transport, memory).registerVoip(token: "voip-1")

        XCTAssertEqual(transport.bodies, [#"{"kind":"voip","platform":"ios","token":"voip-1"}"#])
        XCTAssertNil(memory.lastRegisteredCapabilities())
    }

    /// ⛔ A REFUSED REGISTER REMEMBERS NOTHING, so the next one declares again.
    func testARefusedRegisterRemembersNoCapabilities() async {
        let memory = CapabilityMemory()
        let transport = RepositoryTransport(json: #"{"success":false,"error":"x","code":"rate_limited"}"#, status: 429)

        let result = await repository(transport, memory).register(token: "apns-1")

        XCTAssertEqual(result.failureOnly?.httpStatus, 429)
        XCTAssertNil(memory.lastRegisteredCapabilities())
    }

    /// ⛔ BOTH SIGN-OUT PATHS FORGET THEM, or the next account on this handset would skip
    /// the register that claims the installation.
    func testUnregisterAndForgetClearTheCapabilities() async {
        let memory = CapabilityMemory(token: "apns-1", capabilities: "metaChannels")
        let transport = RepositoryTransport(json: Self.ok)
        let push = repository(transport, memory)

        _ = await push.unregister()
        XCTAssertNil(memory.lastRegisteredCapabilities())

        memory.rememberRegisteredCapabilities("metaChannels")
        push.forgetRegistration()
        XCTAssertNil(memory.lastRegisteredCapabilities())
    }

    /// ⚠️ THE OLD INITIALISER DECLARES NOTHING, so a build that has not opted in registers
    /// exactly as before.
    func testTheOldInitialiserDeclaresNothing() async {
        let transport = RepositoryTransport(json: Self.ok)

        _ = await PushTokenRepository(client: .repositoryTest(transport), memory: CapabilityMemory())
            .register(token: "apns-1")

        XCTAssertEqual(transport.bodies, [#"{"platform":"ios","token":"apns-1"}"#])
    }

    /// Sorted, so the body and the remembered value are deterministic whatever the set's
    /// order.
    func testSeveralCapabilitiesAreSortedOnTheWireAndInMemory() async {
        let memory = CapabilityMemory()
        let transport = RepositoryTransport(json: Self.ok)
        let later = DeviceCapability(rawValue: "aLaterOne")

        _ = await repository(transport, memory, [.metaChannels, later]).register(token: "apns-1")

        XCTAssertEqual(
            transport.bodies,
            [#"{"capabilities":["aLaterOne","metaChannels"],"platform":"ios","token":"apns-1"}"#]
        )
        XCTAssertEqual(memory.lastRegisteredCapabilities(), "aLaterOne,metaChannels")
    }
}

/// A memory that stores the capabilities too, as an app's should.
private final class CapabilityMemory: PushTokenMemory, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    private var voipToken: String?
    private var capabilities: String?

    init(token: String? = nil, capabilities: String? = nil) {
        self.token = token
        self.capabilities = capabilities
    }

    func lastRegisteredToken() -> String? {
        lock.withLock { token }
    }

    func rememberRegisteredToken(_ token: String) {
        lock.withLock { self.token = token }
    }

    func forgetRegisteredToken() {
        lock.withLock { token = nil }
    }

    func lastRegisteredVoipToken() -> String? {
        lock.withLock { voipToken }
    }

    func rememberRegisteredVoipToken(_ token: String) {
        lock.withLock { voipToken = token }
    }

    func forgetRegisteredVoipToken() {
        lock.withLock { voipToken = nil }
    }

    func lastRegisteredCapabilities() -> String? {
        lock.withLock { capabilities }
    }

    func rememberRegisteredCapabilities(_ capabilities: String) {
        lock.withLock { self.capabilities = capabilities }
    }

    func forgetRegisteredCapabilities() {
        lock.withLock { capabilities = nil }
    }
}

/// A memory written before capabilities existed: the protocol's defaults stand in.
private final class TokenOnlyMemory: PushTokenMemory, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(token: String? = nil) {
        self.token = token
    }

    func lastRegisteredToken() -> String? {
        lock.withLock { token }
    }

    func rememberRegisteredToken(_ token: String) {
        lock.withLock { self.token = token }
    }

    func forgetRegisteredToken() {
        lock.withLock { token = nil }
    }

    func lastRegisteredVoipToken() -> String? {
        nil
    }

    func rememberRegisteredVoipToken(_: String) {}
    func forgetRegisteredVoipToken() {}
}
