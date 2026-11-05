import Foundation

/// The assistant's answer to one whisper: whether it acted on the note, and the first
/// words it said after doing so, or why it held the note back.
///
/// Carried by the telemetry event `whisper_applied` (``TelemetryEventType/whisperApplied``),
/// which the voice agent publishes workspace-wide once it has handled a whisper. The
/// envelope's `callId` names the call.
///
/// ⚠️ A RECEIPT ANSWERS THE LATEST NOTE, NOT A PARTICULAR ONE. The event carries no id
/// for the whisper it answers, so a screen clears the receipt it shows when the next
/// note is sent (the website does the same) rather than pairing them.
///
/// ⛔ ``reason`` IS WIRE VOCABULARY AND IS NEVER SHOWN RAW. The website maps it to a
/// sentence per locale; the apps do the same. ⛔ ``firstWords`` IS WHAT THE ASSISTANT SAID
/// TO A CUSTOMER and is customer data: `description` leaves it out.
public struct WhisperReceipt: Sendable, Equatable {
    /// Whether the assistant acted on the note.
    public let applied: Bool
    /// The first words the assistant said after acting on it. ⚠️ `""` when the event sent
    /// none, which a screen words as "acted on it" with no quotation.
    public let firstWords: String
    /// Why the note was not used, when it was not.
    public let reason: Reason?

    public init(applied: Bool, firstWords: String, reason: Reason?) {
        self.applied = applied
        self.firstWords = firstWords
        self.reason = reason
    }

    /// Why the assistant held a note back.
    ///
    /// ⚠️ OPEN-ENDED, like ``TelemetryEventType``: the agent may add a reason, and an
    /// unknown one is kept by name. The website words every reason other than
    /// `taken_over` as the transfer sentence; ``isTakenOver`` is the one test it makes.
    public enum Reason: Sendable, Equatable {
        /// `transfer`: the call is being transferred.
        case transfer
        /// `taken_over`: a team member is holding the call.
        case takenOver
        /// A reason this client does not know, kept as it was sent.
        case unknown(String)

        public init(wire: String) {
            switch wire {
            case "transfer": self = .transfer
            case "taken_over": self = .takenOver
            default: self = .unknown(wire)
            }
        }

        public var wire: String {
            switch self {
            case .transfer: "transfer"
            case .takenOver: "taken_over"
            case let .unknown(name): name
            }
        }

        /// Whether a team member holding the call is the reason.
        public var isTakenOver: Bool {
            self == .takenOver
        }
    }
}

extension WhisperReceipt: CustomStringConvertible, CustomReflectable {
    public var description: String {
        "WhisperReceipt(applied: \(applied), firstWords: <omitted>, reason: \(reason?.wire ?? "nil"))"
    }

    public var customMirror: Mirror {
        Mirror(self, children: [
            "applied": applied,
            "firstWords": "<omitted>",
            "reason": reason?.wire ?? "nil",
        ])
    }
}

public extension TelemetryEnvelope {
    /// The receipt a `whisper_applied` event carries, or nil for any other event or for
    /// one whose `applied` is not a boolean.
    ///
    /// ⚠️ LENIENT ABOUT THE REST, as the website is: a missing or non-string `firstWords`
    /// reads as `""`, and a missing or non-string `reason` as nil. ⛔ STRICT ABOUT
    /// `applied`, which is the one thing a screen cannot guess: reading a malformed one as
    /// false would tell a supervisor their note was ignored.
    var whisperReceipt: WhisperReceipt? {
        guard eventType == .whisperApplied, case let .bool(applied)? = data["applied"] else { return nil }
        return WhisperReceipt(
            applied: applied,
            firstWords: data["firstWords"]?.stringValue ?? "",
            reason: data["reason"]?.stringValue.map(WhisperReceipt.Reason.init(wire:))
        )
    }
}
