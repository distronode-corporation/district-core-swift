import Foundation

// The open vocabularies of the `transcript` v1 events: who spoke, why a transcript ended,
// why lines were retracted, and what an error reports.
//
// ⚠️ EVERY ONE IS OPEN-ENDED BY DESIGN. A name this client does not know decodes to
// `.other` with the name kept, rather than failing the whole frame, and re-encodes as sent:
// the server adds names over time without bumping `v`.

/// Who spoke a line, as the wire names it.
///
/// ⚠️ OPEN-ENDED BY DESIGN. `human_agent` and `supervisor` are reserved for a later v1.x,
/// and any name this client does not know decodes to ``other(_:)`` with the name kept,
/// rather than failing the whole frame. A client labels it as a third party.
public enum TranscriptSpeaker: Sendable, Equatable, Hashable {
    /// `caller`: the person who called (or was called).
    case caller
    /// `agent`: the AI receptionist. ``TranscriptSegment/speakerName`` names the persona.
    case agent
    /// A name this client does not know, kept as it was sent.
    case other(String)

    public init(wire: String) {
        switch wire {
        case "caller": self = .caller
        case "agent": self = .agent
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .caller: "caller"
        case .agent: "agent"
        case let .other(name): name
        }
    }
}

extension TranscriptSpeaker: Codable {
    public init(from decoder: any Decoder) throws {
        try self.init(wire: decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wire)
    }
}

/// Why a live transcript ended.
///
/// ⚠️ OPEN-ENDED, like ``TranscriptSpeaker``: a reason this client does not know is kept.
public enum TranscriptEndReason: Sendable, Equatable, Hashable {
    /// `call_ended`.
    case callEnded
    /// `handed_off`: the call was transferred and the assistant left it.
    case handedOff
    /// `agent_error`.
    case agentError
    case other(String)

    public init(wire: String) {
        switch wire {
        case "call_ended": self = .callEnded
        case "handed_off": self = .handedOff
        case "agent_error": self = .agentError
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .callEnded: "call_ended"
        case .handedOff: "handed_off"
        case .agentError: "agent_error"
        case let .other(name): name
        }
    }
}

extension TranscriptEndReason: Codable {
    public init(from decoder: any Decoder) throws {
        try self.init(wire: decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wire)
    }
}

/// Why lines were retracted. ⚠️ Open-ended, like ``TranscriptEndReason``.
public enum TranscriptRetractReason: Sendable, Equatable, Hashable {
    /// `erased`: the contact was erased.
    case erased
    /// `policy`.
    case policy
    case other(String)

    public init(wire: String) {
        switch wire {
        case "erased": self = .erased
        case "policy": self = .policy
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .erased: "erased"
        case .policy: "policy"
        case let .other(name): name
        }
    }
}

extension TranscriptRetractReason: Codable {
    public init(from decoder: any Decoder) throws {
        try self.init(wire: decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wire)
    }
}

/// What a `transcript_error` reports. ⚠️ Open-ended, like ``TranscriptEndReason``.
public enum TranscriptErrorCode: Sendable, Equatable, Hashable {
    /// `bad_request`: the client sent something malformed. Not retried.
    case badRequest
    /// `unsupported_version`: fall back to the transcript after the call.
    case unsupportedVersion
    /// `not_live`: no live transcript for this call (unknown, another workspace's, ended
    /// over two minutes ago, or not answered by the assistant). ⛔ Never worded as
    /// "forbidden": another workspace's call is indistinguishable from a missing one.
    case notLive
    /// `forbidden_role`: this member's role may not watch.
    case forbiddenRole
    /// `too_many_subscriptions`: more than five on one connection.
    case tooManySubscriptions
    /// `rate_limited`: wait ``TranscriptErrorData/retryAfterMs``.
    case rateLimited
    case other(String)

    public init(wire: String) {
        switch wire {
        case "bad_request": self = .badRequest
        case "unsupported_version": self = .unsupportedVersion
        case "not_live": self = .notLive
        case "forbidden_role": self = .forbiddenRole
        case "too_many_subscriptions": self = .tooManySubscriptions
        case "rate_limited": self = .rateLimited
        default: self = .other(wire)
        }
    }

    public var wire: String {
        switch self {
        case .badRequest: "bad_request"
        case .unsupportedVersion: "unsupported_version"
        case .notLive: "not_live"
        case .forbiddenRole: "forbidden_role"
        case .tooManySubscriptions: "too_many_subscriptions"
        case .rateLimited: "rate_limited"
        case let .other(name): name
        }
    }
}

extension TranscriptErrorCode: Codable {
    public init(from decoder: any Decoder) throws {
        try self.init(wire: decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wire)
    }
}
