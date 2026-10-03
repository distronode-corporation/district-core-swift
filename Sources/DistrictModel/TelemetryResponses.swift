import Foundation

/// `POST /api/district/telemetry/token`: the credential for one workspace's live
/// telemetry socket, and where that socket is. Pinned by
/// `contracts/desktop/district-telemetry-token.json`.
///
/// ⛔ ``token`` IS A BEARER SECRET FOR ONE WORKSPACE, AND THIS TYPE KEEPS IT OUT OF
/// EVERY STRING IT CAN. `description`, `debugDescription` and the mirror all
/// redact it, so a `print`, a string interpolation, a `dump` or an `XCTAssert`
/// failure message never carries it. It is presented in the socket's
/// `Sec-WebSocket-Protocol` header, never in the URL, so it stays out of access
/// logs on the way too.
///
/// ⚠️ ``expiresAt`` IS EPOCH MILLISECONDS BY THE SERVER'S CLOCK, NOT SECONDS. The
/// server closes the socket with 4401 once it passes, so the client replaces the
/// socket a minute before.
public struct TelemetryTokenResponse: Codable, Sendable, Equatable {
    /// `true` on the 200. Checked like every other envelope.
    public let success: Bool

    /// The credential. ⛔ Never log it; see the type note.
    public let token: String

    /// When the credential expires, in epoch milliseconds.
    public let expiresAt: Int64

    /// The socket's address, e.g. `wss://telemetry.example.com/ws/telemetry`.
    ///
    /// ⛔ CHOSEN BY THE WORKSPACE'S REGION, NOT BY WHICH ORIGIN ANSWERED, so always
    /// dial this one: an EU workspace's events are published only to the EU
    /// broadcaster, and a socket to the US one authenticates and then never
    /// delivers anything. ⚠️ `null` only on a server with no broadcaster
    /// configured, which is local development.
    public let wsUrl: String?

    public init(success: Bool, token: String, expiresAt: Int64, wsUrl: String?) {
        self.success = success
        self.token = token
        self.expiresAt = expiresAt
        self.wsUrl = wsUrl
    }

    private enum CodingKeys: String, CodingKey {
        case success
        case token
        case expiresAt
        case wsUrl
    }

    /// ⚠️ WRITTEN BY HAND FOR ONE KEY: a nil ``wsUrl`` is encoded as an explicit
    /// `null`, the way the server sends it, rather than dropped the way synthesised
    /// `Encodable` drops a nil Optional. Decoding is the synthesised behaviour.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(success, forKey: .success)
        try container.encode(token, forKey: .token)
        try container.encode(expiresAt, forKey: .expiresAt)
        try container.encode(wsUrl, forKey: .wsUrl)
    }
}

extension TelemetryTokenResponse: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "TelemetryTokenResponse(success: \(success), token: <redacted>, expiresAt: \(expiresAt), "
            + "wsUrl: \(wsUrl ?? "nil"))"
    }

    public var debugDescription: String {
        description
    }

    /// ⚠️ THE MIRROR TOO, because `dump(_:)` and XCTest's failure messages walk the
    /// mirror rather than calling `description`.
    public var customMirror: Mirror {
        Mirror(self, children: [
            "success": success,
            "token": "<redacted>",
            "expiresAt": expiresAt,
            "wsUrl": wsUrl as Any,
        ])
    }
}

/// What a ``TelemetryEnvelope`` reports.
///
/// ⚠️ OPEN-ENDED BY DESIGN. The server adds event types over time, so a name this
/// client does not know decodes to ``unknown(_:)`` with the name kept rather than
/// failing the whole envelope, and re-encodes as the same name. Treat an unknown
/// event as a hint to read the workspace's state again.
public enum TelemetryEventType: Sendable, Equatable, Hashable {
    /// `call_started`: a call began. The data is the new call.
    case callStarted
    /// `call_updated`: a call in progress changed. The data is the call row.
    case callUpdated
    /// `call_ended`: a call finished. The data may be a six-key projection.
    case callEnded
    /// `call_ringing`: a call is ringing for members on their desktops. The data
    /// is `{callId, userIds}`, ids only. See `DistrictLive.DesktopRingGate`.
    case callRinging
    /// `tool_outcome`: an action the assistant took during a call succeeded or
    /// failed. The data is `{tool, result, provider?, reason?}`.
    case toolOutcome
    /// `message_received`: a message arrived in one of the workspace's threads.
    case messageReceived
    /// `message_sent`: a message was sent from the workspace.
    case messageSent
    /// A name this client does not know, kept as it was sent.
    case unknown(String)

    /// The seven names this client knows, for a table-driven test.
    public static let known: [TelemetryEventType] = [
        .callStarted, .callUpdated, .callEnded, .callRinging, .toolOutcome, .messageReceived, .messageSent,
    ]

    /// Read a wire name.
    public init(wire: String) {
        self = Self.known.first { $0.wire == wire } ?? .unknown(wire)
    }

    /// The name on the wire.
    public var wire: String {
        switch self {
        case .callStarted: "call_started"
        case .callUpdated: "call_updated"
        case .callEnded: "call_ended"
        case .callRinging: "call_ringing"
        case .toolOutcome: "tool_outcome"
        case .messageReceived: "message_received"
        case .messageSent: "message_sent"
        case let .unknown(name): name
        }
    }
}

extension TelemetryEventType: Codable {
    public init(from decoder: any Decoder) throws {
        try self.init(wire: decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wire)
    }
}

/// One frame from the live telemetry socket (`/ws/telemetry`). Pinned by the nine
/// `contracts/desktop/telemetry-event-*.json` fixtures.
///
/// ⛔ AN EVENT IS A HINT, DELIVERED AT MOST ONCE AND ONLY WHILE THE SOCKET IS OPEN.
/// A client that was disconnected, including for the second a renewal takes, has
/// missed whatever happened meanwhile and must read the current state again
/// rather than trusting what earlier events built up.
///
/// ⛔ ``data`` IS CARRIED AS ``WireJSON`` AND NOT MODELLED, BECAUSE THE SERVER HAS
/// NO SINGLE SHAPE FOR IT. Most producers publish the whole Call row; the Sinch
/// bridge publishes a seven-column `call_started` and the LiveKit webhook a
/// six-key `call_ended`; `call_ringing` carries ids only. A struct would have to
/// make every key optional, and would then either drop the explicit nulls the
/// row carries or invent ones the projection never sent. The typed reads the
/// desktop needs are the accessors below, each answering nil for a shape that
/// does not carry its key.
///
/// ⛔ CUSTOMER DATA. A call row carries the caller's number and name, a summary
/// and a transcript, so `description` and the mirror leave ``data`` out.
public struct TelemetryEnvelope: Codable, Sendable, Equatable {
    /// The workspace the event belongs to.
    public let workspaceId: String

    /// The call the event is about. ⚠️ For the two message events this is the
    /// MESSAGE id, and for `tool_outcome` it can be the carrier's call SID.
    public let callId: String

    public let eventType: TelemetryEventType

    /// The event's content, which depends on ``eventType``. See the type note.
    public let data: WireJSON

    /// When the server published the event, an ISO 8601 instant.
    public let timestamp: String

    public init(workspaceId: String, callId: String, eventType: TelemetryEventType, data: WireJSON, timestamp: String) {
        self.workspaceId = workspaceId
        self.callId = callId
        self.eventType = eventType
        self.data = data
        self.timestamp = timestamp
    }

    /// The call's `status` (`ringing`, `in-progress`, `completed`, ...), when the
    /// data carries one as a string.
    public var callStatus: String? {
        data["status"]?.stringValue
    }

    /// The user ids a `call_ringing` event rings, when the data carries the list.
    ///
    /// ⚠️ ONLY THE STRING ELEMENTS. A malformed element names nobody rather than
    /// failing the list, so one bad id cannot stop the right desktop ringing.
    public var ringingUserIds: [String]? {
        data["userIds"]?.arrayValue?.compactMap(\.stringValue)
    }
}

extension TelemetryEnvelope: CustomStringConvertible, CustomReflectable {
    public var description: String {
        "TelemetryEnvelope(workspaceId: \(workspaceId), callId: \(callId), eventType: \(eventType.wire), "
            + "data: <omitted>, timestamp: \(timestamp))"
    }

    public var customMirror: Mirror {
        Mirror(self, children: [
            "workspaceId": workspaceId,
            "callId": callId,
            "eventType": eventType.wire,
            "data": "<omitted>",
            "timestamp": timestamp,
        ])
    }
}
