import Foundation

/// The label a screen shows for an enumerated value the API sends (a call's status,
/// a member's role, a region), in the active language.
///
/// ⛔ WIRE VALUES NEVER LOCALIZE; ONLY THEIR LABELS DO. A screen keeps branching on
/// `"completed"` and shows ``label(_:_:)`` beside it.
///
/// ⛔ AN UNKNOWN VALUE GETS A LOCALIZED GENERIC LABEL, NEVER THE VALUE HUMANIZED. A
/// status the server adds after this build shipped would otherwise appear in English on
/// a French screen. The two exceptions are the contract's own: a transfer reason this
/// build does not know reads as the category's fallback sentence, and an unknown region
/// id is shown upper-cased, which is a code rather than a word in any language.
public enum WireLabel {
    /// The label of `value` in `category`. Matched trimmed and case-insensitively, so
    /// `" Completed "` is `completed`.
    public static func label(_ category: WireCategory, _ value: String?) -> String {
        let key = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let label = WireTable.label(category, key) {
            return label
        }
        if let fallback = WireTable.fallback(category) {
            return fallback
        }
        if category == .region, !key.isEmpty {
            return key.uppercased()
        }
        return WireCopy.genericOther
    }

    /// A region's long name, naming its datacenter: `Canada (Montreal)`. An unknown id is
    /// upper-cased, as ``label(_:_:)`` does.
    public static func regionLongName(_ value: String?) -> String {
        let key = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return WireTable.regionLong(key) ?? label(.region, key)
    }

    /// The label of a placeholder the service stores or sends in English in place of a
    /// real value (`Unknown`, `No summary available.`), or nil for any other text, which
    /// is real data and is shown as it is.
    ///
    /// ⚠️ EXACT MATCH, as the service writes it, in its current spelling or an earlier
    /// one the vocabulary lists under `aliases`: `"No answer \u{2014} no conversation
    /// took place."` is the earlier spelling of `"No answer, no conversation took
    /// place."`, stored rows still hold it, and both get the one label.
    public static func placeholder(_ text: String?) -> String? {
        text.flatMap(WireTable.placeholder)
    }

    /// `values` with every earlier spelling the vocabulary lists for each of them, for a
    /// set that has to recognise a placeholder however a stored row spells it. A value
    /// that is not a vocabulary placeholder passes through on its own.
    public static func spellings(ofPlaceholders values: Set<String>) -> Set<String> {
        values.union(values.flatMap { WireTable.placeholderAliases[$0] ?? [] })
    }
}
