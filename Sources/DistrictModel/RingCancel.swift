import Foundation

/// Why the server ended a ring it started (`call_ring_cancelled`, District AI 3.0.1).
///
/// ⛔ THE WORDING FOLLOWS THE REASON, AND ONLY ``callEnded`` MAY SAY THE CALLER HUNG UP.
/// ``answered`` is "answered on another device"; ``timeout`` and ``withdrawn`` are a missed
/// call; ``declined`` is "declined" (every member rang declined, or this person declined on
/// another of their devices). A screen that said "the caller hung up" for an answer taken
/// elsewhere would tell the person something that did not happen.
///
/// ⚠️ OPEN TO THE SERVER: any other value, or none, reads as ``withdrawn`` and never fails a
/// decode (the contract's rule).
public enum RingCancelReason: Sendable, Equatable, CaseIterable {
    /// Somebody took the call, on some device (possibly this one: see ``RingCancel``).
    case answered
    /// The ring window closed and nobody answered; the AI keeps the call.
    case timeout
    /// The caller hung up while it rang.
    case callEnded
    /// The server stopped ringing for its own reason.
    case withdrawn
    /// Every member the server rang declined, so the ring ended early and the agent takes
    /// a message (7.2.0; `calls/{id}/decline`). ⚠️ A client older than 7.2.0 reads it as
    /// ``withdrawn``, which is why the server could add it.
    case declined

    /// Read a wire value. ⚠️ Unknown or absent is ``withdrawn``.
    public init(wire: String?) {
        self = Self.allCases.first { $0.wire == wire } ?? .withdrawn
    }

    /// The value on the wire.
    public var wire: String {
        switch self {
        case .answered: "answered"
        case .timeout: "timeout"
        case .callEnded: "call_ended"
        case .withdrawn: "withdrawn"
        case .declined: "declined"
        }
    }
}

/// A ring the server has ended, as the background push carries it.
///
/// ⛔ IT ONLY EVER SILENCES A RING, AND NEVER ONE THIS DEVICE ANSWERED. The cancel reaches every
/// device that rang, the answering one included, and can arrive after the answer: a client
/// that has answered (or is answering, or has joined) `callId` ignores it completely, with no
/// hang-up and no summary. A client ringing for `callId` stops the ring and takes the ring's
/// notification away. Anything else ignores it. Matched on `callId` alone.
///
/// ⚠️ A SEPARATE PARSER, NOT A ``PushEvent`` CASE: ``PushPayload/parse(_:)`` routes what a person
/// taps, and this is never tapped (it has no alert), so it keeps dropping the type.
public struct RingCancel: Sendable, Equatable {
    public let workspaceId: String
    public let callId: String
    public let reason: RingCancelReason

    public init(workspaceId: String, callId: String, reason: RingCancelReason) {
        self.workspaceId = workspaceId
        self.callId = callId
        self.reason = reason
    }

    /// The push `type`, verbatim.
    public static let type = "call_ring_cancelled"
    public static let keyReason = "reason"

    /// Parse a push's data map.
    ///
    /// - Returns: the cancel, or nil for any other type or a payload missing either id.
    ///   ⚠️ Values are trimmed and blanks treated as absent, as ``PushPayload`` does; the
    ///   type is matched exactly.
    public static func parse(_ data: [String: String]) -> RingCancel? {
        guard value(data, PushPayload.keyType) == type,
              let workspaceId = value(data, PushPayload.keyWorkspaceId),
              let callId = value(data, PushPayload.keyCallId)
        else { return nil }
        let reason = RingCancelReason(wire: value(data, keyReason))
        return RingCancel(workspaceId: workspaceId, callId: callId, reason: reason)
    }

    /// Parse an APNs `userInfo`: the top-level string pairs, everything else dropped (`aps`
    /// included), as ``PushPayload/parse(userInfo:)`` does.
    public static func parse(userInfo: [AnyHashable: Any]) -> RingCancel? {
        var data: [String: String] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String, let value = value as? String else { continue }
            data[key] = value
        }
        return parse(data)
    }

    private static func value(_ data: [String: String], _ key: String) -> String? {
        guard let raw = data[key] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
