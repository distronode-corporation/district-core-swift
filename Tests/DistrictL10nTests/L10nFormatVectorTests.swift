@testable import DistrictL10n
import Foundation
import XCTest

/// `contracts/i18n/format-vectors.json`, the website's own output, reproduced byte for
/// byte in both languages.
///
/// ⛔ EVERY VECTOR, AND AN EXACT COUNT PER CATEGORY. A path that stopped resolving, or
/// a category renamed upstream, would otherwise iterate nothing and pass.
final class L10nFormatVectorTests: XCTestCase {
    private static let counts = [
        "money": 156, "dates": 16, "times": 16, "durations": 10, "numbers": 7, "percentages": 4,
        "lists": 0, "plurals": 0,
    ]

    func testEveryCategoryIsPresentWithItsVectors() throws {
        let categories = try Self.categories()
        XCTAssertEqual(Set(categories.keys), Set(Self.counts.keys))
        for (name, count) in Self.counts {
            XCTAssertEqual(categories[name]?.count, count, name)
        }
    }

    func testMoney() throws {
        for vector in try Self.vectors("money") {
            let locale = try Self.locale(vector["locale"])
            let options = vector["options"] as? [String: Any] ?? [:]
            let output: String
            switch vector["fn"] as? String {
            case "formatMoney":
                let display: MoneyDisplay = switch options["display"] as? String {
                case "narrow": .narrow
                case "code": .code
                default: .symbol
                }
                output = try L10nFormat.money(
                    minorUnits: Self.int(vector["minorUnits"]),
                    currency: XCTUnwrap(vector["currency"] as? String),
                    display: display,
                    disambiguateDollar: (options["disambiguateDollar"] as? Bool) ?? false,
                    locale: locale
                )
            case "formatMoneyOrBare":
                output = try L10nFormat.moneyOrBare(
                    minorUnits: Self.int(vector["minorUnits"]),
                    currency: vector["currency"] as? String,
                    locale: locale
                )
            case "formatIsoAmount":
                output = try L10nFormat.isoAmount(
                    Self.double(vector["major"]),
                    isoCode: XCTUnwrap(vector["isoCode"] as? String),
                    locale: locale
                )
            default:
                return XCTFail("an unknown money function: \(vector)")
            }
            XCTAssertEqual(output, vector["output"] as? String, "\(vector)")
        }
    }

    func testDates() throws {
        for vector in try Self.vectors("dates") {
            let date = try Self.instant(vector["input"])
            let timezone = try XCTUnwrap(vector["timezone"] as? String)
            let style: DateStyle = switch vector["style"] as? String {
            case "short": .short
            case "long": .long
            case "full": .full
            default: .medium
            }
            for (locale, key) in [(L10nLocale.en, "en"), (.frCA, "fr")] {
                XCTAssertEqual(
                    L10nFormat.date(date, timezone: timezone, style: style, locale: locale),
                    vector[key] as? String,
                    "\(vector)"
                )
            }
        }
    }

    func testTimes() throws {
        for vector in try Self.vectors("times") {
            let date = try Self.instant(vector["input"])
            let timezone = try XCTUnwrap(vector["timezone"] as? String)
            for (locale, key) in [(L10nLocale.en, "en"), (.frCA, "fr")] {
                let output = switch vector["fn"] as? String {
                case "formatTime": L10nFormat.time(date, timezone: timezone, locale: locale)
                default: L10nFormat.dateTime(date, timezone: timezone, locale: locale)
                }
                XCTAssertEqual(output, vector[key] as? String, "\(vector)")
            }
        }
    }

    func testDurations() throws {
        for vector in try Self.vectors("durations") {
            let seconds = try Self.int(vector["seconds"])
            if vector["fn"] as? String == "formatCallDuration" {
                XCTAssertEqual(L10nFormat.callDuration(seconds), vector["output"] as? String)
                continue
            }
            XCTAssertEqual(L10nFormat.minutesSeconds(seconds, locale: .en), vector["en"] as? String)
            XCTAssertEqual(L10nFormat.minutesSeconds(seconds, locale: .frCA), vector["fr"] as? String)
        }
    }

    func testNumbers() throws {
        for vector in try Self.vectors("numbers") {
            let value = try Self.double(vector["value"])
            XCTAssertEqual(L10nFormat.number(value, locale: .en), vector["en"] as? String)
            XCTAssertEqual(L10nFormat.number(value, locale: .frCA), vector["fr"] as? String)
        }
    }

    func testPercentages() throws {
        for vector in try Self.vectors("percentages") {
            let ratio = try Self.double(vector["ratio"])
            XCTAssertEqual(L10nFormat.percent(ratio: ratio, locale: .en), vector["en"] as? String)
            XCTAssertEqual(L10nFormat.percent(ratio: ratio, locale: .frCA), vector["fr"] as? String)
        }
    }

    // MARK: - Reading the file

    static func categories() throws -> [String: [[String: Any]]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contracts/i18n/format-vectors.json")
        let data = try Data(contentsOf: url)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let list = try XCTUnwrap(root["categories"] as? [[String: Any]])
        var out: [String: [[String: Any]]] = [:]
        for category in list {
            let name = try XCTUnwrap(category["category"] as? String)
            out[name] = category["vectors"] as? [[String: Any]] ?? []
        }
        return out
    }

    static func vectors(_ name: String) throws -> [[String: Any]] {
        let vectors = try XCTUnwrap(categories()[name])
        XCTAssertFalse(vectors.isEmpty, name)
        return vectors
    }

    static func locale(_ value: Any?) throws -> L10nLocale {
        switch value as? String {
        case "en": return .en
        case "fr": return .frCA
        default: throw XCTSkip("a vector with no locale: \(String(describing: value))")
        }
    }

    /// ⚠️ THROUGH `NSNumber`, because corelibs-foundation does not bridge a JSON integer
    /// to `Double` with `as?` the way Darwin does.
    static func int(_ value: Any?) throws -> Int {
        try XCTUnwrap(value as? NSNumber).intValue
    }

    static func double(_ value: Any?) throws -> Double {
        try XCTUnwrap(value as? NSNumber).doubleValue
    }

    /// `2026-08-01T12:00:00.000Z`, read by hand so the test depends on no date parser.
    static func instant(_ value: Any?) throws -> Date {
        let text = try XCTUnwrap(value as? String)
        let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        XCTAssertEqual(numbers.count, 7, text)
        var components = DateComponents()
        components.year = numbers[0]
        components.month = numbers[1]
        components.day = numbers[2]
        components.hour = numbers[3]
        components.minute = numbers[4]
        components.second = numbers[5]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return try XCTUnwrap(calendar.date(from: components))
    }
}
