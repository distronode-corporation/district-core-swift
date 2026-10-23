import DistrictL10n
import Foundation

/// A working-hours time FIELD: what it shows for a stored value, and what a typed value
/// saves as.
///
/// ⛔ THE STORED VALUE IS ALWAYS ZERO-PADDED 24-HOUR `HH:MM`, AND THE FIELD IS NOT. The
/// scheduler refuses `9:00` with a 400, so the editors keep the wire string in their drafts;
/// until 7.1.0 they also showed it, which put « 09:00 » on a French screen whose house style
/// is « 9 h », « 9 h 30 » and « 17 h » (the read screens already said « 9 h », through
/// ``SchedulingOverviewSummary/displayTime(_:)``). ``fieldText(_:)`` is the field's text for
/// a stored value, and ``wireValue(_:)`` is the one way back.
///
/// ⚠️ ENGLISH SHOWS THE STORED VALUE UNCHANGED (`09:00`), as before: only the French field
/// changes. Both languages ACCEPT every form below, so a French operator typing `9:30` and an
/// English one typing `9:30` both save `09:30`.
public enum SchedulingWallClock {
    /// The text a time field shows for a stored `HH:MM`: `9 h`, `9 h 30`, `17 h` in French,
    /// the stored value itself in English.
    ///
    /// ⚠️ A STORED VALUE THIS TYPE CANNOT READ COMES BACK UNCHANGED in both languages, so a
    /// half-typed or corrupt draft is shown as it is rather than rewritten into something
    /// plausible.
    public static func fieldText(_ stored: String) -> String {
        guard L10nRuntime.locale == .frCA, wireValue(stored) != nil else { return stored }
        return SchedulingOverviewSummary.displayTime(stored)
    }

    /// What a typed time saves as: zero-padded `HH:MM`, or nil when it is not a time.
    ///
    /// Accepted, with any spaces (including non-breaking ones) around the separator and
    /// either case of `h`: `9 h`, `9 h 30`, `9h30`, `17 h`, `9:30`, `09:30`.
    ///
    /// ⛔ nil FOR ANYTHING ELSE, AND THAT INCLUDES A CLOCK THAT DOES NOT EXIST. The hour is
    /// 0...23 and the minute 0...59 (the web's `hh:mm` input has the same bounds), a minute is
    /// exactly two digits (`9 h 5` is not French and `9:5` is not a time), and a bare `9`
    /// is refused rather than guessed at: the caller shows its catalog's format error.
    public static func wireValue(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let separators = text.filter { $0 == ":" || $0 == "h" }
        guard separators.count == 1, let separator = separators.first else { return nil }
        let halves = text.split(separator: separator, omittingEmptySubsequences: false)
        let hourText = halves[0].trimmingCharacters(in: .whitespaces)
        let minuteText = halves[1].trimmingCharacters(in: .whitespaces)
        // ⚠️ ONLY THE FRENCH FORM MAY OMIT THE MINUTES (`9 h`); `9:` is half a time.
        let minuteDigits = minuteText.isEmpty && separator == "h" ? "00" : minuteText
        guard (1 ... 2).contains(hourText.count), minuteDigits.count == 2,
              isDigits(hourText), isDigits(minuteDigits),
              let hour = Int(hourText), let minute = Int(minuteDigits),
              hour <= 23, minute <= 59
        else { return nil }
        return SchedulingClock.paddedTwo(hour) + ":" + SchedulingClock.paddedTwo(minute)
    }

    /// ⚠️ ASCII DIGITS ONLY. `Int(_:)` already refuses `+9` and `٩`, but `isNumber` would
    /// accept `½`; checking the characters keeps the two in agreement by construction.
    private static func isDigits(_ text: String) -> Bool {
        text.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
