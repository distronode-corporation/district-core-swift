@testable import DistrictData
import DistrictL10n
import XCTest

/// The working-hours time field: « 9 h » on a French screen, `HH:MM` on the wire.
///
/// ⛔ THE BUG THIS HOLDS: the Edit working hours sheet showed the stored « 09:00 » in
/// French, where the house style (and every read screen) says « 9 h ».
final class SchedulingWallClockTests: XCTestCase {
    private typealias Clock = SchedulingWallClock

    // MARK: - What the field shows

    func testFrenchShowsTheHouseStyle() {
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(Clock.fieldText("09:00"), "9 h")
            XCTAssertEqual(Clock.fieldText("09:30"), "9 h 30")
            XCTAssertEqual(Clock.fieldText("17:00"), "17 h")
            XCTAssertEqual(Clock.fieldText("00:05"), "0 h 05")
        }
    }

    /// ⛔ THE SPACES ARE U+0020, as `contracts/i18n/format-vectors.json` writes « 9 h » and
    /// « 13 h 30 », so the edit field and the read screens print the same bytes (and the
    /// same as the other clients' cores). Asserted by code point, since the eye cannot
    /// tell U+0020 from U+00A0.
    func testFrenchSpacesAreU0020LikeTheContractVectors() {
        L10nRuntime.withLocale(.frCA) {
            for (stored, scalars) in [("09:00", [0x39, 0x20, 0x68]), ("09:30", [0x39, 0x20, 0x68, 0x20, 0x33, 0x30])] {
                let text = Clock.fieldText(stored)
                XCTAssertEqual(text.unicodeScalars.map(\.value), scalars.map(UInt32.init), stored)
                XCTAssertEqual(text, SchedulingOverviewSummary.displayTime(stored), stored)
            }
        }
    }

    /// ⚠️ ENGLISH IS UNCHANGED: the field keeps the stored, zero-padded value.
    func testEnglishShowsTheStoredValueUnchanged() {
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(Clock.fieldText("09:00"), "09:00")
            XCTAssertEqual(Clock.fieldText("09:30"), "09:30")
            XCTAssertEqual(Clock.fieldText("17:00"), "17:00")
        }
    }

    /// A draft that is not a time yet is shown as typed, in both languages.
    func testSomethingThatIsNotATimeIsShownAsItIs() {
        for locale in [L10nLocale.en, .frCA] {
            L10nRuntime.withLocale(locale) {
                XCTAssertEqual(Clock.fieldText("9 h 5"), "9 h 5")
                XCTAssertEqual(Clock.fieldText("25:00"), "25:00")
                XCTAssertEqual(Clock.fieldText(""), "")
            }
        }
    }

    // MARK: - What a typed value saves as

    func testEveryAcceptedFormSavesZeroPaddedHHMM() {
        let cases: [(String, String)] = [
            ("9 h", "09:00"),
            ("9 h 30", "09:30"),
            ("9h30", "09:30"),
            ("9:30", "09:30"),
            ("09:30", "09:30"),
            ("17 h", "17:00"),
            ("17h", "17:00"),
            ("9 H 30", "09:30"),
            ("  13 h 05 ", "13:05"),
            ("9\u{00A0}h\u{00A0}30", "09:30"),
            ("9\u{202F}h", "09:00"),
            ("0 h", "00:00"),
            ("23:59", "23:59"),
            ("9 : 30", "09:30"),
        ]
        for (typed, saved) in cases {
            XCTAssertEqual(Clock.wireValue(typed), saved, typed)
        }
    }

    /// ⛔ OUT OF RANGE IS REFUSED, not wrapped or clamped: the caller shows its format error.
    func testAClockThatDoesNotExistIsRefused() {
        for typed in ["24:00", "25 h", "9:60", "9 h 75", "99:99"] {
            XCTAssertNil(Clock.wireValue(typed), typed)
        }
    }

    func testGarbageIsRefused() {
        let garbage = [
            "", " ", "9", "0900", "h", ":", "9:", ":30", "h30", "9 h 5", "9:5", "9:300",
            "123:00", "9h30h", "9:30:00", "9 h:30", "nine h", "9 h trente", "+9:30", "\u{0669}:30",
            "9.30", "1 7 h",
        ]
        for typed in garbage {
            XCTAssertNil(Clock.wireValue(typed), typed)
        }
    }

    /// ⛔ A ROUND TRIP IS THE IDENTITY: what the French field shows saves back as what was
    /// stored, so opening and saving the sheet changes nothing.
    func testTheFrenchFieldRoundTripsToTheStoredValue() {
        L10nRuntime.withLocale(.frCA) {
            for hour in 0 ... 23 {
                for minute in [0, 5, 30, 59] {
                    let stored = SchedulingClock.paddedTwo(hour) + ":" + SchedulingClock.paddedTwo(minute)
                    XCTAssertEqual(Clock.wireValue(Clock.fieldText(stored)), stored, stored)
                }
            }
        }
    }
}
