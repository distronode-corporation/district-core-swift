import Foundation

// The carrier-account, blocking and account settings allowlist entries, in a file of their
// own like `+Setup`. Chained into `allowedExplicitNulls` in `AllowedExplicitNulls+Union.swift`.

extension StrictDecodeVerifier {
    /// ⚠️ ONLY THE NULLS ON DISK. `district-verify-disable.json` OMITS `verifyServiceSid`
    /// rather than nulling it, and `district-settings-unset.json`'s `subscription.updatedAt`
    /// is absent too, so neither gets an entry: an absent key needs no permission.
    static let carrierAndAccount: [String: Set<String>] = [
        // A number the carrier could not resolve: the lookup fills in none of the three.
        //
        //   country, type, carrier   Null when `valid` is false.
        "district-number-lookup-invalid.json": [
            "$.info.carrier",
            "$.info.country",
            "$.info.type",
        ],
        // A workspace with no carrier at all answers `provider: null` beside
        // `connected: false`, and no `providers` map.
        "district-provider-status-none.json": [
            "$.provider",
        ],
        // A trunk created before the route stored Twilio's sids: both columns are nullable
        // and the list serialises them as null.
        "district-sip-trunks.json": [
            "$.trunks[1].domainSid",
            "$.trunks[1].ipAclSid",
        ],
        // A blocked contact with no number on file (`Contact.phone` is nullable).
        "district-contacts-blocked.json": [
            "$.blocked[1].phoneNumber",
        ],
        // The unblock answer clears `blockedAt` and reports the cleared column as null.
        "district-contact-unblock.json": [
            "$.blockedAt",
        ],
        // ⛔ `User.locale` is null for a person who never chose, and the route passes the
        // null through: "never chosen" is a third state, not English.
        "district-settings-unset.json": [
            "$.profile.locale",
        ],
    ]
}
