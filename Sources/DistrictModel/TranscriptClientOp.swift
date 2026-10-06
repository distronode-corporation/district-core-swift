import Foundation

/// The three ops a client sends on the telemetry socket, as text frames.
///
/// ⛔ A SUBSCRIPTION IS PER CONNECTION. After any reconnect or renewal every subscription is
/// sent again; `DistrictLive.TelemetryConnection` does that.
public enum TranscriptClientOp: Sendable, Equatable, Hashable {
    /// Start receiving one call's transcript. The server answers with a snapshot.
    case subscribe(callId: String)
    /// Stop receiving it.
    case unsubscribe(callId: String)
    /// `broadcast: false` stops the workspace-wide `call_*` and `message_*` relay to this
    /// socket. The server's default is true.
    case socketMode(broadcast: Bool)

    /// The `transcript` payload version this client speaks.
    public static let version = 1

    /// The largest frame the server accepts, in bytes.
    ///
    /// ⚠️ NOT CHECKED AT RUN TIME BECAUSE NO FRAME HERE CAN REACH IT: a call id is at most
    /// 64 characters of `[A-Za-z0-9_-]`, which makes the longest op 113 bytes.
    /// A test pins that bound, so a check here would be a line nothing can run.
    public static let maxFrameBytes = 1024

    /// Whether `callId` is a call id the server accepts: 1 to 64 of `A-Z a-z 0-9 _ -`.
    public static func isValidCallId(_ callId: String) -> Bool {
        (1 ... 64).contains(callId.utf8.count) && callId.unicodeScalars.allSatisfy(isCallIdScalar)
    }

    private static func isCallIdScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "A" ... "Z", "a" ... "z", "0" ... "9", "_", "-": true
        default: false
        }
    }

    /// The frame to send, or nil for a call id the server would refuse.
    ///
    /// ⚠️ WRITTEN OUT RATHER THAN ENCODED, in the contract's key order. Safe only because a
    /// valid call id holds nothing JSON escapes, which is why it is validated first.
    public var text: String? {
        switch self {
        case let .subscribe(callId):
            Self.op("transcript.subscribe", callId: callId)
        case let .unsubscribe(callId):
            Self.op("transcript.unsubscribe", callId: callId)
        case let .socketMode(broadcast):
            #"{"op":"socket.mode","v":\#(Self.version),"broadcast":\#(broadcast)}"#
        }
    }

    private static func op(_ name: String, callId: String) -> String? {
        guard isValidCallId(callId) else { return nil }
        return #"{"op":"\#(name)","v":\#(version),"callId":"\#(callId)"}"#
    }
}
