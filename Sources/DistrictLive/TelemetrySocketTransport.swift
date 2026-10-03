import Foundation

/// The one seam between this module and a real WebSocket.
///
/// ⛔ THE `URLSessionWebSocketTask` ADAPTER LIVES IN THE APP, NOT HERE, FOR THE
/// REASON ``HTTPTransport``'s DOES: it is the one piece `swift test` on Linux
/// cannot exercise without a live server, and keeping it in a module with a 100%
/// coverage floor would mean permanently uncoverable lines. Every decision about
/// the socket (what to offer, what to accept, when to renew, when to give up)
/// lives in ``TelemetryConnection`` and is tested here; the adapter only moves
/// bytes.
///
/// What the adapter must do, and the traps in doing it:
///
/// - ``connect(to:subprotocols:)`` returns only once the handshake completed (the
///   delegate's `didOpenWithProtocol`), with the protocol the server selected.
///   It throws for a refused handshake or a network failure.
/// - ⛔ IT MUST SURFACE LIVENESS AS ``TelemetrySocketFrame/heartbeat``.
///   `URLSessionWebSocketTask` answers the server's pings itself and never hands
///   them to `receive()`, so a quiet, healthy socket delivers nothing at all, and
///   the 90 s silence watchdog would drop it every 90 s. Send a ping every 30 s with
///   `sendPing(pongReceiveHandler:)` and yield a heartbeat for each pong.
/// - ⛔ IT MUST REPORT THE SERVER'S CLOSE CODE as ``TelemetrySocketFrame/closed(code:reason:)``
///   (the delegate's `didCloseWith`, or `closeCode` once `receive()` throws), because
///   4401 and 4403 are the protocol: one means "mint again", the other "stop".
///   A close with no code is 1005.
public protocol TelemetrySocketTransport: Sendable {
    /// Open `url`, offering `subprotocols` in order, and return once the handshake
    /// has completed.
    func connect(to url: URL, subprotocols: [String]) async throws -> any TelemetrySocket
}

/// One open socket.
public protocol TelemetrySocket: Sendable {
    /// The subprotocol the server selected in its handshake response, if any.
    var selectedSubprotocol: String? { get }

    /// The next frame. ⚠️ After ``TelemetrySocketFrame/closed(code:reason:)`` the
    /// socket is finished and is not read again; a throw means the connection broke.
    func receive() async throws -> TelemetrySocketFrame

    /// Close with a normal closure (1000) and stop reading. ⚠️ Idempotent, and
    /// called on sockets that may already be closed.
    func close() async
}

/// What a socket can deliver.
public enum TelemetrySocketFrame: Sendable, Equatable {
    /// A text message: one telemetry envelope, as JSON.
    case text(String)
    /// A binary message. ⚠️ The server sends text; binary is read the same way.
    case binary(Data)
    /// Proof the socket is alive and carrying nothing: a ping from the server or a
    /// pong to the adapter's own ping. See the ⛔ on ``TelemetrySocketTransport``.
    case heartbeat
    /// The server closed the socket with `code`.
    case closed(code: Int, reason: String)
}
