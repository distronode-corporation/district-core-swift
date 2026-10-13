import Foundation

/// The refusals this client writes itself, before a request is sent: catalog sentences
/// in the active language, carried as ``ApiError``'s `message` with no code.
///
/// ⛔ ONE LIST, AND EVERY REFUSAL THE CORE BUILDS FROM CATALOG TEXT IS ON IT. It is how
/// `ApiError.localizedMessage` tells this client's own sentence, which is already in the
/// reader's language, from a server's English sentence that carried no code, which must
/// never reach a French screen. A refusal added to the catalog and left off this list
/// would read as nil in French, so `scripts/gen-l10n.py --check` fails unless this list
/// names exactly the `core.toml` entries whose `ctx` is `error`.
package enum ClientRefusal {
    /// Every refusal sentence in the active language.
    package static var sentences: Set<String> {
        [
            DeskCopy.logoEmpty,
            DeskCopy.logoSize,
            DeskCopy.logoType,
            DeskCopy.settingsEmpty,
            InboxCopy.attachmentEmpty,
            InboxCopy.attachmentSize,
            InboxCopy.attachmentType,
            InboxCopy.draftBlank,
        ]
    }

    /// Whether `message` is one of this client's own refusals in the active language.
    package static func isOwn(_ message: String) -> Bool {
        sentences.contains(message)
    }
}
