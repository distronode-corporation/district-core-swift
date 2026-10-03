import DistrictModel
import DistrictNetwork
import Foundation

/// Where a ``TelemetryConnection`` gets its credentials.
///
/// ⚠️ A PROTOCOL SO THE CONNECTION IS TESTED WITHOUT AN ``ApiClient``. The client
/// conforms below; the tests pass a scripted minter.
public protocol TelemetryTokenMinter: Sendable {
    /// A fresh credential for `workspaceId`'s socket.
    func mintTelemetryToken(workspaceId: String) async -> Result<TelemetryTokenResponse, ApiError>
}

extension ApiClient: TelemetryTokenMinter {
    public func mintTelemetryToken(workspaceId: String) async -> Result<TelemetryTokenResponse, ApiError> {
        await telemetryToken(workspaceId: workspaceId)
    }
}

/// The two calls a ``PresenceController`` makes.
public protocol PresenceAPI: Sendable {
    /// Register this Mac's presence under `token`, or renew it.
    func registerPresence(token: String) async -> Result<Void, ApiError>

    /// Withdraw this installation's registrations. ⛔ EVERY kind, see
    /// ``PresenceController/signOut()``.
    func unregisterPresence() async -> Result<Void, ApiError>
}

extension ApiClient: PresenceAPI {
    /// ⛔ ALWAYS `platform: "macos"`. `kind: "desktop"` is accepted only from a
    /// desktop platform, and the only desktop this package serves is the Mac; the
    /// iOS pairing is a 400. See ``PushTokenKind``.
    ///
    /// ⚠️ ENVELOPE-CHECKED: a 200 that does not affirm `success` is
    /// ``ApiError/decoding(_:)``, and the controller treats it as a failed renewal.
    public func registerPresence(token: String) async -> Result<Void, ApiError> {
        let descriptor = DistrictEndpoints.registerPushToken(token: token, kind: .desktop, platform: .macos)
        return await affirmed("PresenceRegisterResponse", send(descriptor, as: SuccessResponse.self))
    }

    public func unregisterPresence() async -> Result<Void, ApiError> {
        await affirmed(
            "PresenceUnregisterResponse",
            send(DistrictEndpoints.unregisterPushToken(), as: SuccessResponse.self)
        )
    }

    private func affirmed(_ name: String, _ outcome: Result<SuccessResponse, ApiError>) -> Result<Void, ApiError> {
        outcome.flatMap { $0.success ? .success(()) : .failure(.decoding("\(name) did not affirm success=true")) }
    }
}
