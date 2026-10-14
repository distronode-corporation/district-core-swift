import Foundation

// The signed-in person's own settings, `/api/settings`. The same for every workspace
// they hold: the route reads the `User` row, plus the plan and region of the FIRST
// workspace `getWorkspacesForUser` returns.
//
// ⚠️ A `//` HEADER RATHER THAN A `///` ONE: SwiftFormat's `docComments` rule rejects a
// doc comment attached to no declaration.

/// `GET /api/settings`.
///
/// Pinned by `district-settings.json` (a person who chose French, on a paid `ca`
/// workspace) and `district-settings-unset.json` (a person who never chose, with no
/// workspace at all).
public struct AccountSettingsResponse: Codable, Sendable {
    public let profile: AccountProfile
    public let subscription: AccountSubscription
    /// The first workspace's data region (`us`, `ca`, `eu`, `apac`), or `us` when the
    /// person holds no workspace. Display only: there is no write path.
    public let region: String
}

/// The person's own row.
///
/// ⛔ ``locale`` IS NULLABLE AND NULL IS A THIRD STATE, NOT ENGLISH. The column has no
/// default and null means "never chosen", the state in which the website's language
/// cookie speaks for the account. The route passes it through as an explicit `null`
/// (unlike ``timezone``, which it defaults), so a client that read null as `en` and
/// wrote it back would record a choice nobody made.
public struct AccountProfile: Codable, Sendable {
    public let email: String
    /// `""` when unset: the route substitutes the empty string rather than sending null.
    public let displayName: String
    /// `America/Toronto` when unset: the route substitutes it.
    public let timezone: String
    /// `en`, `fr`, or nil for "never chosen". The stored value, not a language tag.
    public let locale: String?
}

/// The first workspace's plan, as `/api/settings` words it.
///
/// ⚠️ NOT THE SAME FACT AS ``WorkspaceBilling/subscriptionTier``: this route SUBSTITUTES
/// `Free` for a null tier and `none` for a null status, where `workspace/billing`
/// passes the columns through. A screen must not compare the two.
public struct AccountSubscription: Codable, Sendable {
    public let tier: String
    public let status: String
    /// ISO-8601. ⚠️ ABSENT, not null, when the person holds no workspace.
    public let updatedAt: String?
}

/// `POST /api/settings`.
///
/// Pinned by `district-settings-save.json`. ``message`` is the route's fixed English
/// sentence and is never shown: a screen words its own confirmation.
public struct AccountSettingsSaveResponse: Codable, Sendable {
    public let success: Bool
    public let message: String
}
