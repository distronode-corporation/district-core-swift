import Foundation

/// The six steps of the setup wizard, in the order the service lists them.
public enum SetupStep: String, Codable, Sendable, CaseIterable {
    case business
    case number
    case receptionist
    case callers
    case calls
    case golive
}

/// What the owner did with a step. ⚠️ The service accepts exactly these three values; a step
/// left out of a PATCH keeps the state it had.
public enum SetupStepState: String, Codable, Sendable, CaseIterable {
    case todo
    case done
    case skipped
}

public extension SetupSteps {
    /// The state of one step as the service answered it, or nil when it sent none or a value
    /// this client does not know.
    func state(of step: SetupStep) -> SetupStepState? {
        let raw: String? = switch step {
        case .business: business
        case .number: number
        case .receptionist: receptionist
        case .callers: callers
        case .calls: calls
        case .golive: golive
        }
        return raw.flatMap(SetupStepState.init(rawValue:))
    }
}

/// `POST /api/district/setup/lookup`: a draft of the business's facts, read off its own website.
///
/// ⛔ A SUGGESTION, NEVER A WRITE. The service stores nothing; the owner reviews the draft and
/// saves what they keep through `PATCH /api/district/setup`. Every service and FAQ arrives
/// `enabled: false`.
public struct SetupLookupResponse: Codable, Sendable, Equatable {
    public let draft: SetupLookupDraft
    public let source: SetupLookupSource
}

/// The drafted facts. ⚠️ `address` and `weeklyHours` stay ``WireJSON``: they go back to the
/// service unchanged inside a `businessFacts` PATCH, and the service owns their validation.
public struct SetupLookupDraft: Codable, Sendable, Equatable {
    public let address: WireJSON?
    public let weeklyHours: WireJSON?
    public let services: [SetupDraftService]
    public let faqs: [SetupDraftFaq]
    /// How many drafted items the service dropped as unsupported by the page's text.
    public let dropped: Int
}

/// One service on the business's website. `price` is free text, read aloud as written.
public struct SetupDraftService: Codable, Sendable, Equatable {
    public let name: String
    public let price: String?
    public let enabled: Bool

    public init(name: String, price: String?, enabled: Bool) {
        self.name = name
        self.price = price
        self.enabled = enabled
    }
}

/// One question and answer on the business's website.
public struct SetupDraftFaq: Codable, Sendable, Equatable {
    public let question: String
    public let answer: String
    public let enabled: Bool

    public init(question: String, answer: String, enabled: Bool) {
        self.question = question
        self.answer = answer
        self.enabled = enabled
    }
}

/// Where a draft came from. Today always `kind: "website"` with the page actually read.
public struct SetupLookupSource: Codable, Sendable, Equatable {
    public let kind: String
    public let url: String
}

/// The 422 `website_unreadable` body of a lookup. ⚠️ ``ApiError`` keeps the `code` and the
/// message only, so `reason` (`host_unavailable`, `blocked_scheme`, `invalid_url` and the other
/// page refusals) is here for the contract gate and for a caller that reads the body itself.
public struct SetupLookupRefusal: Codable, Sendable, Equatable {
    public let error: String
    public let code: String
    public let reason: String
}

/// `POST /api/district/setup/test-call`: the receptionist is calling the owner's phone.
public struct SetupTestCallResponse: Codable, Sendable, Equatable {
    public let success: Bool
    public let callId: String
}

/// `GET` and `POST /api/district/setup/forwarding-check`: whether the business line forwards
/// to the District number. The POST answers 202 with the same body.
public struct ForwardingCheckResponse: Codable, Sendable, Equatable {
    /// False when this region has no verifier configured; the step then offers no check.
    public let available: Bool
    /// The latest check, or nil before the first one.
    public let forwardingCheck: ForwardingCheck?
    /// Checks left today.
    public let attemptsLeft: Int
}

/// Which calls the owner says their line forwards.
public enum ForwardingCheckMode: String, Codable, Sendable, CaseIterable {
    case all
    case unanswered
}

/// One forwarding check. ⚠️ The status, carrier and failure are kept as strings: the service
/// owns those vocabularies and a new value must not fail the decode.
public struct ForwardingCheck: Codable, Sendable, Equatable {
    public let id: String
    /// `pending`, `passed` or `failed`.
    public let status: String
    public let mode: String
    public let businessLine: String
    public let startedAt: String
    public let at: String
    public let verifierNumber: String
    public let carrier: String
    public let failure: String?
    /// The District number the check call arrived on, once it did.
    public let arrivedOn: String?
    /// Set when a newer check replaced this one before it finished.
    public let supersededAt: String?

    public var isPending: Bool {
        status == "pending"
    }

    public var hasPassed: Bool {
        status == "passed"
    }
}

/// `GET /api/district/connections`: the workspace's connected providers.
///
/// ⚠️ A VIEWER GETS THE ROWS WITHOUT ``calendar``, so its absence is not "no calendar".
public struct ConnectionsResponse: Codable, Sendable, Equatable {
    public let connections: [WorkspaceConnection]
    public let calendar: CalendarResolution?

    /// Whether a calendar the receptionist can book into is connected.
    public var hasActiveCalendar: Bool {
        calendar?.activeProvider != nil
    }
}

/// One connection row, as stored.
public struct WorkspaceConnection: Codable, Sendable, Equatable {
    public let provider: String
    public let status: String
}

/// Which calendar the receptionist books into, and why that one. Both are null when none is
/// connected.
public struct CalendarResolution: Codable, Sendable, Equatable {
    public let activeProvider: String?
    public let source: String?
}
