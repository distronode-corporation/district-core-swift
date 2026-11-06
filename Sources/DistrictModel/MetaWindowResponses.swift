import Foundation

/// `GET /api/district/messages/send?workspaceId&channel&to`, whether the composer may reply
/// on Messenger or Instagram to `to` now, and how.
///
/// ⛔ A PREVIEW, NEVER THE GATE, like ``WhatsAppWindowResponse``. The send applies the same
/// rule itself and answers 409 `messenger_window_closed` (Instagram too) when the window has
/// shut between this read and the send, so a caller handles that refusal whatever this said.
///
/// ⚠️ THE GET SITS ON THE SEND'S OWN PATH. Method plus path is still unique: the POST is
/// ``EndpointID/sendMessage``, this read is ``EndpointID/metaWindow``.
public struct MetaWindowResponse: Codable, Sendable {
    public let success: Bool
    public let window: MetaWindow
}

/// Meta's reply window on one customer, as the server reads it.
public struct MetaWindow: Codable, Sendable, Equatable {
    public let state: MetaWindowState
    /// ISO-8601, when this state ends; nil when the window is closed.
    ///
    /// ⚠️ NOT A COUNTDOWN TO SHOW. The website shows none for Meta, and neither do the apps.
    public let until: String?

    public init(state: MetaWindowState, until: String?) {
        self.state = state
        self.until = until
    }
}

/// Which reply Meta allows now.
///
/// ⚠️ OPEN-ENDED, like ``WhisperReceipt/Reason``: a state this client does not know is kept
/// by name as ``unknown(_:)``, and ⛔ AN UNKNOWN STATE BLOCKS NOTHING, as the website treats
/// it. The send is the gate.
public enum MetaWindowState: Codable, Sendable, Equatable {
    /// `open`: within 24 hours of the customer's last message. Any reply goes.
    case open
    /// `human_agent`: within 7 days, on an asset with Meta's human agent tag turned on. The
    /// reply goes tagged `HUMAN_AGENT`, which Meta allows for a person's reply only, so a
    /// composer does not offer the AI draft.
    case humanAgent
    /// `closed`: no reply goes until the customer writes again.
    case closed
    /// A state this client does not know, kept as it was sent.
    case unknown(String)

    public init(wire: String) {
        switch wire {
        case "open": self = .open
        case "human_agent": self = .humanAgent
        case "closed": self = .closed
        default: self = .unknown(wire)
        }
    }

    public var wire: String {
        switch self {
        case .open: "open"
        case .humanAgent: "human_agent"
        case .closed: "closed"
        case let .unknown(name): name
        }
    }

    public init(from decoder: Decoder) throws {
        try self.init(wire: decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wire)
    }
}
