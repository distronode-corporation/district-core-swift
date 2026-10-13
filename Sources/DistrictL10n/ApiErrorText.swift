import Foundation

/// The sentence a screen shows for an API error code, in the active language.
///
/// ⛔ THE CODE IS THE CONTRACT, NOT THE SERVER'S `error` TEXT. That text is English
/// whatever the reader's language, because a route has no locale in scope; the code is
/// a stable name every client can translate. The table is generated from
/// `contracts/i18n/api-errors.json`, the website's own catalog, so a code reads the same
/// sentence on every surface.
public enum ApiErrorText {
    /// The response header that carries the code when the route left its body alone.
    public static let header = "X-Distronode-Error-Code"

    /// The sentence for `code`, or nil for a code this build does not know (an older app
    /// against a newer server).
    ///
    /// - Parameter items: what the refusal lists, for the two codes whose sentence
    ///   names them (`invalid_params`, `REGIONS_DEGRADED`), joined with commas as the
    ///   website joins them. Empty gives the sentence without the list; every other code
    ///   ignores it.
    public static func sentence(for code: String, items: [String] = []) -> String? {
        ApiErrorTable.sentence(code, items: items.isEmpty ? nil : items.joined(separator: ", "))
    }

    /// The contract's own sentence for a failure nothing names: `unknown`.
    public static var unknown: String {
        ApiErrorCopy.unknown
    }
}
