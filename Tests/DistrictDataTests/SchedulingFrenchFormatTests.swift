@testable import DistrictData
import DistrictL10n
import DistrictModel
import Foundation
import XCTest

/// ⛔ THE SCHEDULING FORMATTERS' FRENCH, HELD TO THE WEBSITE'S OWN OUTPUT. These
/// formatters fill a catalog's `{day}`, `{hour}` and `{clock}` themselves rather than
/// calling ``L10nFormat``'s `date` and `time`, so the vector test in `DistrictL10nTests`
/// never sees them: this file reads the same `contracts/i18n/format-vectors.json` and
/// checks every French date and time they print against it, `1er` and `15 h 04` among
/// them. English is held byte for byte by the other scheduling tests, which this change
/// left as they were; the English lines here are the same values, restated beside the
/// French they pair with.
final class SchedulingFrenchFormatTests: XCTestCase {
    // MARK: - The vectors

    /// `formatDateTime`'s French is the developer stamp's and the bookings table's.
    func testDateTimesMatchTheWebsitesFrench() throws {
        let vectors = try Self.vectors("times").filter { $0["fn"] as? String == "formatDateTime" }
        XCTAssertEqual(vectors.count, 8)
        for vector in vectors {
            let input = try XCTUnwrap(vector["input"] as? String)
            let timezone = try XCTUnwrap(vector["timezone"] as? String)
            let french = try XCTUnwrap(vector["fr"] as? String)
            L10nRuntime.withLocale(.frCA) {
                XCTAssertEqual(SchedulingDeveloperFormat.stamp(input, timezone: timezone), french, "\(vector)")
                XCTAssertEqual(
                    SchedulingBookingFormat.bookingDateTime(startAt: input, timezone: timezone),
                    french,
                    "\(vector)"
                )
            }
        }
    }

    /// `formatTime`'s French is the register's clock and the working hours' windows.
    func testTimesMatchTheWebsitesFrench() throws {
        let vectors = try Self.vectors("times").filter { $0["fn"] as? String == "formatTime" }
        XCTAssertEqual(vectors.count, 8)
        for vector in vectors {
            let instant = try XCTUnwrap(WireInstant.parse(XCTUnwrap(vector["input"] as? String)))
            let timezone = try XCTUnwrap(vector["timezone"] as? String)
            let local = try XCTUnwrap(vector["local"] as? String)
            let french = try XCTUnwrap(vector["fr"] as? String)
            L10nRuntime.withLocale(.frCA) {
                let parts = SchedulingClock.parts(of: instant, timezone: timezone)
                XCTAssertEqual(SchedulingClock.clock(parts), french, "\(vector)")
                XCTAssertEqual(SchedulingOverviewSummary.displayTime(local), french, "\(vector)")
            }
        }
    }

    /// The medium date is the override date's, in both languages, `1er` included.
    func testOverrideDatesMatchTheWebsitesMediumDate() throws {
        let vectors = try Self.vectors("dates").filter { $0["style"] as? String == "medium" }
        XCTAssertEqual(vectors.count, 4)
        for vector in vectors {
            // Every date vector is noon UTC, the same calendar day in its zone.
            let day = try String(XCTUnwrap(vector["input"] as? String).prefix(10))
            for (locale, key) in [(L10nLocale.en, "en"), (.frCA, "fr")] {
                L10nRuntime.withLocale(locale) {
                    XCTAssertEqual(SchedulingHoursFormat.formatOverrideDate(day), vector[key] as? String, "\(vector)")
                }
            }
        }
    }

    // MARK: - Each formatter, French beside English

    /// ⛔ 24-HOUR, AN EMPTY MERIDIEM AND NO SPACE LEFT AT THE END, where English keeps
    /// its inherited twelve-hour clock.
    func testTheDeveloperStampIsTwentyFourHourInFrench() {
        let afternoon = "2026-09-12T19:04:00Z"
        let first = "2026-08-01T13:00:00Z"
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(
                SchedulingDeveloperFormat.stamp(afternoon, timezone: "America/Toronto"),
                "12 sept. 2026, 15 h 04"
            )
            XCTAssertEqual(
                SchedulingDeveloperFormat.stamp(first, timezone: "America/Toronto"),
                "1er ao\u{FB}t 2026, 9 h"
            )
            XCTAssertEqual(
                SchedulingDeveloperFormat.stamp("2026-09-12T00:05:00Z", timezone: "UTC"),
                "12 sept. 2026, 0 h 05"
            )
            XCTAssertEqual(SchedulingDeveloperFormat.stamp("soon", timezone: "UTC"), "Date inconnue")
        }
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(
                SchedulingDeveloperFormat.stamp(afternoon, timezone: "America/Toronto"),
                "Sep 12, 2026, 03:04 PM"
            )
            XCTAssertEqual(SchedulingDeveloperFormat.stamp(first, timezone: "America/Toronto"), "Aug 1, 2026, 09:00 AM")
        }
    }

    func testTheBookingsTableReadsTheFirstAndTheClockInFrench() {
        let first = "2026-08-01T13:05:00Z"
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(
                SchedulingBookingFormat.bookingDateTime(startAt: first, timezone: "America/Toronto"),
                "1er ao\u{FB}t 2026, 9 h 05"
            )
        }
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(
                SchedulingBookingFormat.bookingDateTime(startAt: first, timezone: "America/Toronto"),
                "Aug 1, 2026, 9:05"
            )
        }
    }

    func testTheRegisterReadsTheFirstAndTheClockInFrench() throws {
        let now = try XCTUnwrap(WireInstant.parse("2026-07-20T12:00:00Z"))
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(
                SchedulingOverviewSummary.bookingWhen(startAt: "2026-08-01T10:00:00Z", timezone: "UTC", now: now),
                "1er ao\u{FB}t, 10 h"
            )
            XCTAssertEqual(
                SchedulingOverviewSummary.bookingWhen(startAt: "2026-07-20T14:30:00Z", timezone: "UTC", now: now),
                "Aujourd'hui \u{E0} 14 h 30"
            )
        }
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(
                SchedulingOverviewSummary.bookingWhen(startAt: "2026-08-01T10:00:00Z", timezone: "UTC", now: now),
                "Aug 1, 10:00"
            )
        }
    }

    /// The windows read `9 h \u{E0} 17 h`; a value whose halves are not both numbers keeps
    /// the English shape, as it does in English.
    func testWorkingHoursWindowsReadTheFrenchClock() {
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(SchedulingOverviewSummary.displayTime("09:00"), "9 h")
            XCTAssertEqual(SchedulingOverviewSummary.displayTime("17:05"), "17 h 05")
            XCTAssertEqual(SchedulingOverviewSummary.displayTime("9:ab"), "9:ab")
            XCTAssertEqual(SchedulingOverviewSummary.displayTime("ab:30"), "ab:30")
            XCTAssertEqual(SchedulingOverviewSummary.displayTime("0900"), "0900")
        }
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(SchedulingOverviewSummary.displayTime("09:00"), "9:00")
        }
    }

    /// ⛔ A RANGE INSIDE ONE YEAR SAYS THE YEAR ONCE IN FRENCH TOO. The French date has no
    /// comma before its year, so the English tail never matched and every French range
    /// kept both years.
    func testAnOverrideRangeInsideOneYearSaysTheYearOnceInFrench() {
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(
                SchedulingHoursFormat.formatOverrideDates(start: "2026-12-24", end: "2026-12-26"),
                "24 d\u{E9}c. \u{E0} 26 d\u{E9}c. 2026"
            )
            XCTAssertEqual(
                SchedulingHoursFormat.formatOverrideDates(start: "2026-08-01", end: "2026-08-03"),
                "1er ao\u{FB}t \u{E0} 3 ao\u{FB}t 2026"
            )
            XCTAssertEqual(
                SchedulingHoursFormat.formatOverrideDates(start: "2026-12-30", end: "2027-01-01"),
                "30 d\u{E9}c. 2026 \u{E0} 1er janv. 2027"
            )
            XCTAssertEqual(
                SchedulingHoursFormat.formatOverrideDates(start: "2026-99-12", end: "2026-09-14"),
                "2026-99-12 \u{E0} 14 sept. 2026"
            )
        }
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(
                SchedulingHoursFormat.formatOverrideDates(start: "2026-12-24", end: "2026-12-26"),
                "Dec 24 to Dec 26, 2026"
            )
        }
    }

    func testTheDayOfTheMonthIsFirstOnlyInFrench() {
        XCTAssertEqual(L10nFormat.dayOfMonth(1, locale: .frCA), "1er")
        XCTAssertEqual(L10nFormat.dayOfMonth(2, locale: .frCA), "2")
        XCTAssertEqual(L10nFormat.dayOfMonth(1, locale: .en), "1")
        XCTAssertEqual(L10nFormat.frenchClock(hour: 0, minute: 5), "0 h 05")
        XCTAssertEqual(L10nFormat.frenchClock(hour: 9, minute: 0), "9 h")
    }

    // MARK: - Reading the file

    private static func vectors(_ name: String) throws -> [[String: Any]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("contracts/i18n/format-vectors.json")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let categories = try XCTUnwrap(root["categories"] as? [[String: Any]])
        let category = try XCTUnwrap(categories.first { $0["category"] as? String == name })
        return try XCTUnwrap(category["vectors"] as? [[String: Any]])
    }
}
