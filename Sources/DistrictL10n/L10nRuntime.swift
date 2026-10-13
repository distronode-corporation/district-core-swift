import Foundation

/// The languages the core writes its text in.
///
/// ⛔ CANADIAN FRENCH IS THE ONLY FRENCH, AND EVERY FRENCH DEVICE GETS IT. A device set
/// to fr-FR, fr-BE or fr-CH reads the same strings as one set to fr-CA; see
/// ``locale(fromPreferred:)``.
public enum L10nLocale: String, CaseIterable, Equatable, Sendable {
    case en
    case frCA = "fr-CA"

    /// The BCP 47 tag this client sends as `Accept-Language`.
    public var languageTag: String {
        rawValue
    }

    /// The value `POST /api/settings` stores in `User.locale`.
    ///
    /// ⚠️ NOT THE LANGUAGE TAG. The route's schema is `z.enum(["en", "fr"])`, the set of
    /// copy catalogs the website has, and answers 400 to `fr-CA`.
    public var settingsValue: String {
        switch self {
        case .en: "en"
        case .frCA: "fr"
        }
    }
}

/// Which language the core's strings and formats are in right now.
///
/// ⛔ THE APP SETS ``locale`` ONCE AT LAUNCH, AND AGAIN WHENEVER THE DEVICE LANGUAGE
/// CHANGES. Nothing in this package reads the device's language itself: the core has
/// no idea which list of preferred languages the app was given, and a second reading of
/// it would let the app's own screens and the core's sentences disagree. Until the app
/// sets it, it is ``L10nLocale/en``, which is how the 7.x apps keep French off.
///
/// ⚠️ A TASK-LOCAL OVERRIDE WINS OVER THE STORED VALUE. Tests run English and French
/// side by side through ``withLocale(_:_:)``, and a test that set the shared value
/// instead would turn every assertion running beside it French.
public enum L10nRuntime {
    /// The language every string and format in this package is produced in.
    public static var locale: L10nLocale {
        get { scoped ?? store.locale }
        set { store.locale = newValue }
    }

    /// The language for the current task and the tasks it starts, over ``locale``.
    @TaskLocal public static var scoped: L10nLocale?

    /// Run `body` with every string and format in `locale`, leaving the stored value
    /// alone.
    public static func withLocale<T>(_ locale: L10nLocale, _ body: () throws -> T) rethrows -> T {
        try $scoped.withValue(locale, operation: body)
    }

    /// True once every catalog entry has a reviewed French translation. The apps keep
    /// French off while this is false: until then the French text is the English.
    public static var isFrenchComplete: Bool {
        FR_COMPLETE
    }

    private static let store = LocaleStore()
}

/// The stored language, behind a lock because the app writes it from the main thread
/// while any task may be reading it.
private final class LocaleStore: @unchecked Sendable {
    private let lock = NSLock()
    private var value = L10nLocale.en

    var locale: L10nLocale {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            value = newValue
        }
    }
}

/// The language for a device whose preferred languages are `tags`, most preferred
/// first (`Locale.preferredLanguages`, `Bundle.preferredLocalizations`).
///
/// ⛔ THE FIRST TAG THIS CORE HAS A LANGUAGE FOR DECIDES, AND ANY FRENCH IS CANADIAN
/// FRENCH. `fr-FR` before `en-US` gives French; `en-US` before `fr-CA` gives English,
/// because that person put English first; `de-DE` then `fr-CH` gives French, the first
/// language this core can speak. A list with neither gives English. This is how Apple
/// resolves a bundle localized in `en` and `fr-CA` against the same list, so the core
/// and the app's own screens choose alike.
///
/// ⚠️ ONLY THE LANGUAGE SUBTAG IS READ, case-insensitively, with `-` or `_` as the
/// separator: `fr`, `FR_ca` and `fr-Latn-BE` are all French.
public func locale(fromPreferred tags: [String]) -> L10nLocale {
    for tag in tags {
        let language = tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { $0.lowercased() }
        switch language {
        case "fr": return .frCA
        case "en": return .en
        default: continue
        }
    }
    return .en
}
