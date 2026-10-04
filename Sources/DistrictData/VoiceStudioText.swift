import DistrictModel
import Foundation

/// The Studio sentences a client has to build itself, filled from the service's own templates.
///
/// ⛔ NO WORD HERE IS TYPED IN A CLIENT. The read carries the web's sentences with their
/// placeholders left in (`labels.meterAbout` is "About {ms} ms", or "Environ {ms} ms" for a
/// French-preference reader), so an unsaved edit's meter and the "Based on" line follow the
/// portal language exactly as the server's own sentences do (Sean, 2026-10-03: "Follow the
/// portal language").
///
/// ⚠️ EACH PLACEHOLDER IS REPLACED ONCE, AS LITERAL TEXT: no format strings, no patterns. A
/// recipe name is the service's and may hold anything, so the count is filled first, and a
/// recipe called "{n}" stays "{n}".
public enum VoiceStudioText {
    static let msPlaceholder = "{ms}"
    static let recipePlaceholder = "{recipe}"
    static let countPlaceholder = "{n}"

    /// The unit after a bare measured median, as the templates write it: a no-break space,
    /// then `ms`, in both locales.
    static let unit = "\u{00A0}ms"

    /// The meter's headline.
    ///
    /// ⛔ "AT LEAST", NEVER "ABOUT", WHEN A STAGE IS MISSING: the missing stage is not estimated,
    /// so the real time is longer than the sum.
    public static func headline(_ headline: VoiceStudioMeterHeadline, labels: VoiceStudioLabels) -> String {
        switch headline {
        case let .server(text):
            text
        case let .local(ms, atLeast):
            fill(atLeast ? labels.meterAtLeast : labels.meterAbout, msPlaceholder, with: grouped(ms, labels))
        case .none:
            labels.meterNone
        }
    }

    /// A leg's or a stage's words.
    public static func latency(_ text: VoiceStudioLatencyText, labels: VoiceStudioLabels) -> String {
        switch text {
        case let .server(sentence):
            sentence
        case let .milliseconds(ms):
            grouped(ms, labels) + unit
        case .none:
            labels.notMeasured
        }
    }

    /// "Based on Fastest, 2 changes.", or nil when there is nothing to say: no change, or a
    /// recipe this tier does not name.
    public static func basedOn(recipe: String, changes: Int, labels: VoiceStudioLabels) -> String? {
        guard changes > 0, !recipe.isEmpty else { return nil }
        if changes == 1 {
            return fill(labels.basedOnOne, recipePlaceholder, with: recipe)
        }
        let counted = fill(labels.basedOnMany, countPlaceholder, with: String(changes))
        return fill(counted, recipePlaceholder, with: recipe)
    }

    /// A whole number of milliseconds with the portal locale's separator between groups of
    /// three digits from the right (`1,234`, `1 234`); none below 1000.
    ///
    /// ⚠️ NOT THE DEVICE'S LOCALE: the labels are in the PORTAL language, and a number grouped
    /// for a phone set to German inside a French sentence would be neither.
    public static func grouped(_ ms: Double, _ labels: VoiceStudioLabels) -> String {
        let digits = Array(String(Int(ms.rounded())))
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 {
                out += labels.numberGrouping
            }
            out.append(digit)
        }
        return out
    }

    /// `template` with its first `placeholder` replaced by `value`; unchanged when it has none.
    static func fill(_ template: String, _ placeholder: String, with value: String) -> String {
        guard let range = template.range(of: placeholder) else { return template }
        return template.replacingCharacters(in: range, with: value)
    }
}
