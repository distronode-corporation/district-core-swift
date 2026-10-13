@testable import DistrictData
import DistrictL10n
import DistrictModel
import XCTest

/// ⛔ THE FRENCH SMOKE TEST FOR THE SCHEDULING FORMATTERS: under French, the calendar's
/// words come from `DistrictL10n`'s French tables with no locale passed anywhere, and
/// the catalog sentences keep their English until their French lands. English is held
/// byte for byte by every other test in this target.
final class SchedulingFrenchSmokeTests: XCTestCase {
    func testTheCalendarWordsFollowTheLanguage() {
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(SchedulingClock.monthName(9), "sept.")
            XCTAssertEqual(SchedulingClock.monthNames.last, "d\u{E9}c.")
            XCTAssertEqual(SchedulingHoursFormat.weekDayNames.first, "lundi")
            XCTAssertEqual(SchedulingSettingsFormat.weekStartLabel(0), "dimanche")
            XCTAssertEqual(SchedulingOverviewSummary.displayDays.first, "lun.")
            XCTAssertEqual(SchedulingHoursFormat.formatOverrideDate("2026-09-21"), "sept. 21, 2026")
        }
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(SchedulingClock.monthName(9), "Sep")
            XCTAssertEqual(SchedulingHoursFormat.weekDayNames.first, "Monday")
            XCTAssertEqual(SchedulingOverviewSummary.displayDays.first, "Mon")
        }
    }

    /// Counts are grouped the French way, and the catalog text is still English.
    func testCatalogSentencesUseFrenchNumbersAndKeepTheirEnglish() {
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(SchedulingBookingFormat.minutesLabel(1204), "1\u{00A0}204 min")
            XCTAssertEqual(SchedulingBookingView.upcoming.label, "Upcoming")
            XCTAssertEqual(SchedulingTeamFormat.districtRoleLabel("agency"), "Agency")
        }
    }
}
