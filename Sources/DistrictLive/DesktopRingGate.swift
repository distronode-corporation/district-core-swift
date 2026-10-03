import DistrictModel
import Foundation

/// The call ringing on this Mac.
public struct DesktopRing: Sendable, Equatable {
    public let workspaceId: String
    public let callId: String
    /// When the ring started, in milliseconds, on the caller's injected clock.
    public let startedAtMilliseconds: Int64
}

/// Why a ring stopped.
public enum DesktopRingEnd: Sendable, Equatable {
    /// `call_ended` for the call.
    case callEnded
    /// A `call_updated` whose status can no longer be answered.
    case noLongerAnswerable(status: String)
    /// Nobody answered within ``DesktopRingGate/ringTimeoutMilliseconds``.
    case timedOut
    /// The app silenced it: answered, declined, signed out, or about to sleep.
    case cleared
}

/// What the gate asks the app to do.
public enum DesktopRingCommand: Sendable, Equatable {
    /// Start the ringtone and show Answer and Decline for this call.
    case startRinging(workspaceId: String, callId: String)
    /// Stop the ringtone and take the ring away.
    case stopRinging(workspaceId: String, callId: String, reason: DesktopRingEnd)
    /// Call ``DesktopRingGate/expire(atMilliseconds:)`` after this long.
    case scheduleTimeout(afterMilliseconds: Int64)
}

/// Decides when this Mac rings, from the telemetry events, as a pure state machine.
///
/// ⛔ A RING STARTS ONLY FOR THIS MEMBER. A `call_ringing` event reaches every socket
/// open on the workspace and names the members it rings by user id (the `sub` of
/// their bearer, see `DistrictAuthCore.AccessClaims`), so the gate is built with
/// this session's user id and ignores a ring for a colleague.
///
/// ⛔ ONE RING AT A TIME. A second call that rings while one is ringing here is left
/// alone; the server hands that caller back to the receptionist when its own window
/// closes.
///
/// A ring ends when:
///
/// - `call_ended` arrives for the call;
/// - a `call_updated` for the call carries a status the answer route would refuse.
///   ⛔ "REFUSE" IS NOT "ANYTHING BUT `ringing`". The route answers a call whose
///   status is `in-progress` or `ringing` (`ANSWERABLE_CALL_STATUSES`), and an
///   inbound call being handed over by the receptionist is `in-progress` for the
///   whole ring, with `call_updated` events arriving as its live transcript grows.
///   Ending on "not ringing" would end every ring at the first transcript line. An
///   update with no status says nothing about it;
/// - ``ringTimeoutMilliseconds`` pass with nobody answering. ⛔ That is the longest
///   the server holds a caller for an answer, and the ring deliberately does not end
///   sooner: ending first would take Answer away while the server would still have
///   taken it, which turns a slow hand into a missed call;
/// - the app clears it (``clear()``).
///
/// ⛔ NOTHING IS SENT TO THE SERVER WHEN A RING ENDS WITHOUT AN ANSWER, for the
/// reason `DistrictCall.IncomingCallController` gives: a decline and a ring nobody
/// heard must look the same from outside.
public struct DesktopRingGate: Sendable, Equatable {
    /// The longest the server holds a caller for an answer (30 s, also the longest
    /// ring a workspace may choose).
    public static let ringTimeoutMilliseconds: Int64 = 30000

    /// The statuses the answer route accepts.
    public static let answerableStatuses: Set<String> = ["in-progress", "ringing"]

    /// This session's user id.
    public let userId: String

    /// The call ringing now, if any.
    public private(set) var ring: DesktopRing?

    public init(userId: String) {
        self.userId = userId
    }

    /// Apply one telemetry event received at `now` (milliseconds).
    public mutating func handle(_ envelope: TelemetryEnvelope, atMilliseconds now: Int64) -> [DesktopRingCommand] {
        switch envelope.eventType {
        case .callRinging:
            return ringing(envelope, now: now)
        case .callEnded:
            return end(envelope, reason: .callEnded)
        case .callUpdated:
            guard let status = envelope.callStatus, !Self.answerableStatuses.contains(status) else { return [] }
            return end(envelope, reason: .noLongerAnswerable(status: status))
        case .callStarted, .toolOutcome, .messageReceived, .messageSent, .unknown:
            return []
        }
    }

    /// The timeout the gate asked for came due. ⚠️ Re-checks the fact rather than
    /// trusting the timer: a timer armed for a ring that already ended, or for an
    /// earlier ring than this one, does nothing.
    public mutating func expire(atMilliseconds now: Int64) -> [DesktopRingCommand] {
        guard let ring, ringHasExpired(atMilliseconds: now) else { return [] }
        self.ring = nil
        return [.stopRinging(workspaceId: ring.workspaceId, callId: ring.callId, reason: .timedOut)]
    }

    /// Whether the ring has run out at `now`. False when nothing is ringing.
    public func ringHasExpired(atMilliseconds now: Int64) -> Bool {
        guard let ring else { return false }
        return now &- ring.startedAtMilliseconds >= Self.ringTimeoutMilliseconds
    }

    /// Silence the ring: it was answered or declined, the member signed out, or the
    /// Mac is about to sleep.
    public mutating func clear() -> [DesktopRingCommand] {
        guard let ring else { return [] }
        self.ring = nil
        return [.stopRinging(workspaceId: ring.workspaceId, callId: ring.callId, reason: .cleared)]
    }

    private mutating func ringing(_ envelope: TelemetryEnvelope, now: Int64) -> [DesktopRingCommand] {
        guard ring == nil, envelope.ringingUserIds?.contains(userId) == true else { return [] }
        ring = DesktopRing(workspaceId: envelope.workspaceId, callId: envelope.callId, startedAtMilliseconds: now)
        return [
            .startRinging(workspaceId: envelope.workspaceId, callId: envelope.callId),
            .scheduleTimeout(afterMilliseconds: Self.ringTimeoutMilliseconds),
        ]
    }

    private mutating func end(_ envelope: TelemetryEnvelope, reason: DesktopRingEnd) -> [DesktopRingCommand] {
        guard let ring, ring.workspaceId == envelope.workspaceId, ring.callId == envelope.callId else { return [] }
        self.ring = nil
        return [.stopRinging(workspaceId: ring.workspaceId, callId: ring.callId, reason: reason)]
    }
}
