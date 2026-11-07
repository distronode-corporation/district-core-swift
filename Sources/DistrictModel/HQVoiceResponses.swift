import Foundation

/// District HQ by voice: the answers of the four voice routes, the screen report, and the
/// packets the voice agent sends in its LiveKit room. Read off core-rust's
/// `district-model/src/hq_voice.rs`, which the Windows and Linux apps ship, and the
/// service's routes under `/api/district/hq/`.
///
/// ⛔ THE ROOM IS JOINED ONLY WHEN IT IS AN HQ ROOM AND ENCRYPTED
/// (``HQVoiceTokenResponse/isJoinable``), and only on a member's action: each token starts
/// a billed session (``HQVoice/sessionSeconds``).
public enum HQVoice {
    /// Every HQ voice room's name starts with this; the client never builds one.
    public static let roomPrefix = "hq_"
    /// The data topic the agent sends proposals and their resolutions on.
    public static let proposalTopic = "hq.proposal"
    /// The text-stream topic of the transcription.
    public static let transcriptionTopic = "lk.transcription"
    /// The stream attribute naming one transcribed segment.
    public static let segmentIDAttribute = "lk.segment_id"
    /// The stream attribute naming the track that was transcribed: the member's own
    /// microphone track means the member's words.
    public static let transcribedTrackIDAttribute = "lk.transcribed_track_id"
    /// The stream attribute set to `"true"` on a segment's final text.
    public static let transcriptionFinalAttribute = "lk.transcription_final"
    /// The agent participant's attribute carrying ``HQAgentState``.
    public static let agentStateAttribute = "lk.agent.state"
    /// How long a session lasts. Each token starts one, billed.
    public static let sessionSeconds: TimeInterval = 30 * 60
    /// The most earlier console turns a token request carries.
    public static let historyMaxTurns = 6
    /// The most characters of one turn a token request carries.
    public static let historyMaxCharacters = 500
    /// The service's `code` when the workspace has used its voice minutes. Its `error`
    /// is the sentence to show; the text console keeps working.
    public static let allowanceReachedCode = "hq_voice_allowance_reached"
}

/// One earlier console turn sent with a token request, so the agent knows the
/// conversation so far.
public struct HQVoiceTurn: Sendable, Equatable {
    public enum Role: String, Sendable {
        case user
        case model
    }

    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }

    /// The turns a token request carries: the LAST ``HQVoice/historyMaxTurns`` with any
    /// non-blank text, each trimmed and cut to ``HQVoice/historyMaxCharacters``, as the
    /// service bounds them.
    public static func bounded(_ turns: [HQVoiceTurn]) -> [HQVoiceTurn] {
        turns.compactMap { turn -> HQVoiceTurn? in
            let text = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return HQVoiceTurn(role: turn.role, text: String(text.prefix(HQVoice.historyMaxCharacters)))
        }
        .suffix(HQVoice.historyMaxTurns)
        .map(\.self)
    }
}

/// `POST /api/district/hq/voice-token`: a LiveKit credential for one HQ voice session.
///
/// ⛔ `token` AND `sessionId` ARE SECRETS: they are left out of ``description`` and
/// ``debugDescription``, so logging this value never prints them.
public struct HQVoiceTokenResponse: Codable, Sendable, Equatable {
    public struct E2EE: Codable, Sendable, Equatable {
        /// The room's passphrase, handed to the LiveKit key provider verbatim.
        public let key: String

        public init(key: String) {
            self.key = key
        }
    }

    public let success: Bool
    public let token: String
    /// The server to join, exactly as sent.
    public let url: String
    /// `hq_<workspace>_<uuid>`, new for each session.
    public let roomName: String
    /// Where the voice is processed (`us` today). Shown before the microphone starts:
    /// for a ca, eu or apac workspace it is the disclosure that voice leaves the region.
    public let processingRegion: String
    /// `push` or anything else; see ``micMode``.
    public let micModeWire: String
    public let sessionId: String
    public let e2ee: E2EE?

    private enum CodingKeys: String, CodingKey {
        case success, token, url, roomName, processingRegion, sessionId, e2ee
        case micModeWire = "micMode"
    }

    public init(
        success: Bool,
        token: String,
        url: String,
        roomName: String,
        processingRegion: String,
        micModeWire: String,
        sessionId: String,
        e2ee: E2EE?
    ) {
        self.success = success
        self.token = token
        self.url = url
        self.roomName = roomName
        self.processingRegion = processingRegion
        self.micModeWire = micModeWire
        self.sessionId = sessionId
        self.e2ee = e2ee
    }

    /// Whether the room may be joined: an HQ room AND a non-blank encryption key. A room
    /// without a key is never joined.
    public var isJoinable: Bool {
        guard roomName.hasPrefix(HQVoice.roomPrefix), let key = e2ee?.key else { return false }
        return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// How the microphone behaves: ``HQMicMode/push`` only for `push`, an open
    /// microphone for anything else, an unknown value included.
    public var micMode: HQMicMode {
        HQMicMode(wire: micModeWire)
    }
}

extension HQVoiceTokenResponse: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "HQVoiceTokenResponse(roomName: \(roomName), url: \(url), processingRegion: \(processingRegion), "
            + "micMode: \(micModeWire), token: <redacted>, sessionId: <redacted>, e2ee: "
            + "\(e2ee == nil ? "none" : "<redacted>"))"
    }

    public var debugDescription: String {
        description
    }
}

/// How the member's microphone behaves in a session.
public enum HQMicMode: Sendable, Equatable {
    /// Muted until held.
    case push
    /// Open while the session is live.
    case open

    public init(wire: String) {
        self = wire == "push" ? .push : .open
    }
}

/// The member's own HQ voice settings in one workspace.
public struct HQVoiceSettings: Codable, Sendable, Equatable {
    public let voice: String
    public let length: String
    public let pace: String
    public let language: String
    public let micMode: String

    public init(voice: String, length: String, pace: String, language: String, micMode: String) {
        self.voice = voice
        self.length = length
        self.pace = pace
        self.language = language
        self.micMode = micMode
    }
}

/// `GET` and `PUT /api/district/hq/voice-settings`.
public struct HQVoiceSettingsResponse: Codable, Sendable, Equatable {
    public let success: Bool
    public let settings: HQVoiceSettings
}

/// `POST /api/district/hq/voice-context`: the screen was recorded.
public struct HQVoiceContextResponse: Codable, Sendable, Equatable {
    public let success: Bool
}

/// `POST /api/district/hq/proposals/cancel`: the proposal was cancelled.
public struct HQProposalCancelResponse: Codable, Sendable, Equatable {
    public let success: Bool
}

/// The kind of record a screen report names.
public enum HQVoiceRecordKind: String, Sendable, Equatable {
    case call
    case contact
    case conversation
}

/// The record open on screen: its kind and its id, never anything that names a person.
public struct HQVoiceSelection: Sendable, Equatable {
    /// The longest id the service accepts.
    public static let idMaxLength = 128

    public let kind: HQVoiceRecordKind
    public let id: String

    /// The record, or nil when the service would refuse the id (empty, over
    /// ``idMaxLength``, or with a character outside ASCII letters, digits, `_` and `-`):
    /// a report naming it would be refused whole.
    public init?(kind: HQVoiceRecordKind, id: String) {
        guard !id.isEmpty, id.count <= Self.idMaxLength,
              id.unicodeScalars
              .allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-") })
        else { return nil }
        self.kind = kind
        self.id = id
    }
}

/// What is on the member's screen during a session, the `snapshot` of a voice-context
/// report. Free of personal data by construction: a page id from the service's page table
/// and, at most, a record's id.
public struct HQVoiceScreen: Sendable, Equatable {
    /// The session's count of reports, from 1.
    public let version: Int
    /// A page id of the service's page table (`hq`, `calls`, `inbox`, ...).
    public let page: String
    public let selected: HQVoiceSelection?

    public init(version: Int, page: String, selected: HQVoiceSelection? = nil) {
        self.version = version
        self.page = page
        self.selected = selected
    }
}

/// A change the voice agent proposed. Nothing has been changed yet.
public struct HQVoiceProposal: Sendable, Equatable {
    public let proposalId: String
    /// The write, for example `update_persona`. Not for display.
    public let tool: String
    /// The write's arguments, returned untouched on confirmation.
    public let args: WireJSON
    /// One sentence saying what the change would do. May be empty.
    public let summary: String

    public init(proposalId: String, tool: String, args: WireJSON, summary: String) {
        self.proposalId = proposalId
        self.tool = tool
        self.args = args
        self.summary = summary
    }
}

/// What became of a proposal the member resolved by voice.
public enum HQResolutionStatus: String, Sendable, Equatable {
    case applied
    case failed
    case cancelled
}

/// A proposal resolved by voice. A click's own answer says what became of a clicked one.
public struct HQVoiceResolution: Sendable, Equatable {
    public let proposalId: String
    public let status: HQResolutionStatus
    /// Why a change could not be made, in English: for diagnostics, not for a screen.
    public let error: String?
    /// A live call the member can join, on an applied takeover.
    public let joinCallId: String?

    public init(proposalId: String, status: HQResolutionStatus, error: String?, joinCallId: String?) {
        self.proposalId = proposalId
        self.status = status
        self.error = error
        self.joinCallId = joinCallId
    }
}

/// One packet the agent sends on ``HQVoice/proposalTopic``.
public enum HQVoicePacket: Sendable, Equatable {
    case proposal(HQVoiceProposal)
    case resolved(HQVoiceResolution)

    /// The packet in `payload`, or nil for anything that is not one: not JSON, not an
    /// object, an unknown type, or a required field missing, empty or of the wrong kind.
    /// Never throws. Unknown fields are ignored.
    ///
    /// The web client's rules: a proposal needs a non-empty id and tool, an object of
    /// arguments and a string summary (which may be empty); a resolution needs a non-empty
    /// id, one of the three statuses and `via` equal to `voice`. Only a non-empty `error`
    /// is kept, and a `joinCall` only on an applied change with a non-empty `callId`.
    public static func read(_ payload: Data) -> HQVoicePacket? {
        guard let packet = try? JSONDecoder().decode(WireJSON.self, from: payload),
              case let .object(fields) = packet,
              let type = fields["type"]?.stringValue
        else { return nil }
        func filled(_ key: String) -> String? {
            fields[key]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
        }
        switch type {
        case "HQ_PROPOSAL":
            guard let proposalId = filled("proposalId"), let tool = filled("tool"),
                  let args = fields["args"], args.objectValue != nil,
                  let summary = fields["summary"]?.stringValue
            else { return nil }
            return .proposal(HQVoiceProposal(proposalId: proposalId, tool: tool, args: args, summary: summary))
        case "HQ_PROPOSAL_RESOLVED":
            guard let proposalId = filled("proposalId"),
                  let status = fields["status"]?.stringValue.flatMap(HQResolutionStatus.init(rawValue:)),
                  fields["via"]?.stringValue == "voice"
            else { return nil }
            let joinCall = status == .applied
                ? fields["joinCall"]?["callId"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
                : nil
            return .resolved(HQVoiceResolution(
                proposalId: proposalId,
                status: status,
                error: filled("error"),
                joinCallId: joinCall
            ))
        default:
            return nil
        }
    }
}

/// The agent's state, from its ``HQVoice/agentStateAttribute``.
public enum HQAgentState: String, Sendable, Equatable {
    case listening
    case thinking
    case speaking

    /// The state, or nil for a value this client does not know.
    public init?(wire: String) {
        self.init(rawValue: wire)
    }
}
