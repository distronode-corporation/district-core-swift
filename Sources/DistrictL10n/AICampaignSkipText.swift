import Foundation

/// The sentence a campaign results screen shows beside one contact, from the row's `code`.
///
/// ⛔ THE SERVER OWNS EVERY ONE OF THESE DECISIONS (DNC, calling hours, country, billing).
/// This table only names them; nothing here decides whether a contact may be called.
///
/// ⚠️ TWO SOURCES, ONE LOOKUP. Every code the route can put on a row is in the service's
/// error catalog (``ApiErrorText``) except `sinch_contact_required` and
/// `sinch_disclosure_unsupported`, which the service's shared AI calling chain names but
/// its error catalog does not, so their sentences live in `core.toml`.
public enum AICampaignSkipText {
    /// The sentence for `code` in the active language, or nil for a code this build does
    /// not know (an older app against a newer server).
    public static func sentence(for code: String) -> String? {
        switch code {
        case "sinch_contact_required": CampaignCopy.sinchContactRequired
        case "sinch_disclosure_unsupported": CampaignCopy.sinchDisclosureUnsupported
        default: ApiErrorText.sentence(for: code)
        }
    }
}
