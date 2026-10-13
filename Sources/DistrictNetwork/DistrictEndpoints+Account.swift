import DistrictL10n
import Foundation

/// The signed-in person's own settings, the same for every workspace they hold.
public extension DistrictEndpoints {
    /// Tell the server which language to write to this person in: email, Voice Studio
    /// and any other server text.
    ///
    /// ⛔ ONLY `locale` IS SENT. The route updates exactly the `profile` keys present, so
    /// a body that also carried `displayName` or `timezone` would overwrite what the
    /// person set on the web with whatever this app last read.
    ///
    /// ⚠️ THE STORED VALUE IS `en` OR `fr`, NOT THE LANGUAGE TAG: the route's schema is
    /// `z.enum(["en", "fr"])` and answers 400 to `fr-CA`. See
    /// ``L10nLocale/settingsValue``.
    ///
    /// ⚠️ LAST WRITER WINS against the website's language menu, by decision: the app
    /// writes on sign-in and whenever the device language changes.
    static func saveLocale(_ locale: L10nLocale) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .saveLocale,
            .post,
            DistrictPaths.accountSettings,
            body: .json(.object([("profile", .object([("locale", .string(locale.settingsValue))]))]))
        )
    }
}
