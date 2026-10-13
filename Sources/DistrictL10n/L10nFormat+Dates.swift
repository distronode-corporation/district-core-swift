import Foundation

/// How much of a date to write. The website's `DateStyle`, which is `Intl`'s.
public enum DateStyle: Sendable, Equatable {
    /// `2026-08-01` in both languages.
    case short
    /// `Aug 1, 2026` / `1er août 2026`.
    case medium
    /// `August 1, 2026` / `1er août 2026`.
    case long
    /// `Saturday, August 1, 2026` / `samedi 1er août 2026`.
    case full
}

public extension L10nFormat {
    /// The date of `date` in the IANA zone `timezone`, the website's `formatDate`.
    ///
    /// ⚠️ THE ZONE IS THE READER'S PROFILE ZONE, NOT THE DEVICE'S. A zone this
    /// platform does not know is read as UTC, as the website's retry without the zone
    /// does on a UTC server.
    ///
    /// ⛔ FRENCH FOLLOWS THE GLOSSARY OVER CLDR: the first of a month is `1er`.
    static func date(
        _ date: Date,
        timezone: String,
        style: DateStyle = .medium,
        locale: L10nLocale = L10nRuntime.locale
    ) -> String {
        let parts = ZonedParts(date, timezone: timezone)
        if style == .short {
            return "\(parts.year)-\(twoDigits(parts.month))-\(twoDigits(parts.day))"
        }
        // `pick` cannot miss: a Gregorian calendar only yields months 1...12 and
        // weekdays 1...7, so the tables are indexed directly.
        switch locale {
        case .en:
            let month = style == .medium
                ? Tables.monthAbbreviationsEn[parts.month - 1]
                : Tables.monthNamesEn[parts.month - 1]
            let text = "\(month) \(parts.day), \(parts.year)"
            return style == .full ? Tables.weekdayNamesEn[parts.weekday - 1] + ", " + text : text
        case .frCA:
            let month = style == .medium
                ? Tables.monthAbbreviationsFr[parts.month - 1]
                : Tables.monthNamesFr[parts.month - 1]
            let day = parts.day == 1 ? "1er" : String(parts.day)
            let text = "\(day) \(month) \(parts.year)"
            return style == .full ? Tables.weekdayNamesFr[parts.weekday - 1] + " " + text : text
        }
    }

    /// The time of day of `date` in `timezone`, the website's `formatTime`.
    ///
    /// ⛔ THE HOUR CYCLE IS THE ZONE'S, NOT THE LANGUAGE'S ALONE: English reads a
    /// 12-hour clock (`3:04 p.m.`) only in an `America/` or `Australia/` zone and a
    /// 24-hour one (`15:04`) elsewhere; French is always 24-hour, with the OQLF's
    /// `15 h 04` and `9 h` for a whole hour.
    static func time(_ date: Date, timezone: String, locale: L10nLocale = L10nRuntime.locale) -> String {
        let parts = ZonedParts(date, timezone: timezone)
        switch locale {
        case .en:
            guard timezone.hasPrefix("America/") || timezone.hasPrefix("Australia/") else {
                return "\(twoDigits(parts.hour)):\(twoDigits(parts.minute))"
            }
            let hour = parts.hour % 12 == 0 ? 12 : parts.hour % 12
            return "\(hour):\(twoDigits(parts.minute)) " + (parts.hour < 12 ? "a.m." : "p.m.")
        case .frCA:
            return parts.minute == 0 ? "\(parts.hour) h" : "\(parts.hour) h \(twoDigits(parts.minute))"
        }
    }

    /// The medium date and the time together, the website's `formatDateTime`:
    /// `Sep 21, 2026, 3:04 p.m.` / `21 sept. 2026, 15 h 04`.
    static func dateTime(_ date: Date, timezone: String, locale: L10nLocale = L10nRuntime.locale) -> String {
        self.date(date, timezone: timezone, style: .medium, locale: locale)
            + ", " + time(date, timezone: timezone, locale: locale)
    }

    /// `05`, `12`.
    internal static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }
}

/// The wall-clock fields of an instant in one zone.
private struct ZonedParts {
    let year: Int
    let month: Int
    let day: Int
    let weekday: Int
    let hour: Int
    let minute: Int

    init(_ date: Date, timezone: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .gmt
        year = calendar.component(.year, from: date)
        month = calendar.component(.month, from: date)
        day = calendar.component(.day, from: date)
        weekday = calendar.component(.weekday, from: date)
        hour = calendar.component(.hour, from: date)
        minute = calendar.component(.minute, from: date)
    }
}
