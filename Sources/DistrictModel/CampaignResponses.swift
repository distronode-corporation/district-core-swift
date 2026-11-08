import DistrictL10n
import Foundation

/// `POST /api/district/calls/outbound`: one AI campaign launch, pinned by
/// `district-calls-outbound.json`.
///
/// ⛔ ``success`` ONLY MEANS THE BATCH WAS PROCESSED, NOT THAT ANY CALL WENT OUT. With no
/// trunk configured every contact comes back `failed` while the request itself is a clean
/// 200, and a contact on the DNC list, outside its calling hours or in a country the
/// workspace may not auto-dial comes back `skipped`. Read ``queuedCount`` (or each row of
/// ``results``) before telling the operator anything was placed, as the web's dialer does.
///
/// ⚠️ A CONTACT CAN BE MISSING FROM ``results``. The route skips a contact that is not the
/// workspace's or has no phone number without a row, so `results.count` can be smaller than
/// the number of contacts asked for.
///
/// ⚠️ A WORKSPACE REFUSAL IS NOT A ROW. Billing, overage, dormancy, the rate limit and a
/// missing provider refuse the whole batch with an HTTP error and a `code`, before any call.
public struct AICampaignLaunchResponse: Codable, Sendable, Equatable {
    /// ⛔ The batch was processed. Not that any call was queued; see the type note.
    public let success: Bool
    public let results: [AICampaignContactResult]

    /// How many contacts the voice agent is now calling.
    public var queuedCount: Int {
        results.count(where: { $0.status == .queued })
    }
}

/// One contact's outcome in a campaign launch.
public struct AICampaignContactResult: Codable, Sendable, Equatable {
    public let contactId: String
    public let status: AICampaignContactStatus
    /// The carrier-facing call id, on a queued row only.
    public let callId: String?
    /// The voice provider the call went through (`twilio`, `telnyx`, ...), on a queued row
    /// only. A wire value, never display text.
    public let provider: String?
    /// The carrier account the call went through, on a queued row only.
    public let accountId: String?
    /// The server's English detail, on a skipped or failed row. ⛔ Never shown on a French
    /// screen; see ``localizedMessage``.
    public let error: String?
    /// Why a skipped row was skipped (`auto_dial_contact_opted_out`,
    /// `auto_dial_outside_hours`, ...). A failed row carries none.
    public let code: String?

    public init(
        contactId: String,
        status: AICampaignContactStatus,
        callId: String? = nil,
        provider: String? = nil,
        accountId: String? = nil,
        error: String? = nil,
        code: String? = nil
    ) {
        self.contactId = contactId
        self.status = status
        self.callId = callId
        self.provider = provider
        self.accountId = accountId
        self.error = error
        self.code = code
    }

    /// The sentence to show beside this contact in the reader's language, or nil when the
    /// screen should show its own.
    ///
    /// ⛔ A KNOWN ``code`` READS THE CATALOG IN BOTH LANGUAGES, so a skip reads the same
    /// sentence the web shows for it. Without one it is ``error`` in English and nil in
    /// French, as for ``ApiError/localizedMessage``: never the English wire text on a
    /// French screen. A queued row has nothing to say.
    public var localizedMessage: String? {
        if let code, let sentence = AICampaignSkipText.sentence(for: code) {
            return sentence
        }
        return L10nRuntime.locale == .en ? error : nil
    }
}

/// What happened to one contact.
///
/// ⚠️ OPEN-ENDED, like ``MetaWindowState``: a status this client does not know is kept by
/// name as ``unknown(_:)`` rather than failing the decode. The calls are already placed by
/// the time this body arrives, so a decode failure would hide queued calls from the operator.
public enum AICampaignContactStatus: Codable, Sendable, Equatable {
    /// The voice agent is calling this contact.
    case queued
    /// The server's rules refused this contact (DNC, hours, country); see the row's `code`.
    case skipped
    /// The dial itself failed.
    case failed
    /// A status this client does not know, kept as it was sent.
    case unknown(String)

    public init(wire: String) {
        switch wire {
        case "queued": self = .queued
        case "skipped": self = .skipped
        case "failed": self = .failed
        default: self = .unknown(wire)
        }
    }

    public var wire: String {
        switch self {
        case .queued: "queued"
        case .skipped: "skipped"
        case .failed: "failed"
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
