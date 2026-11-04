import Foundation

/// The thread assignment write and the WhatsApp composer's two reads (app parity).
///
/// ⚠️ A SIBLING FILE BECAUSE `DistrictPaths.swift` SITS NEAR SwiftLint's 500-LINE
/// `file_length`, the reason `DistrictPaths+Numbers.swift` exists.
extension DistrictPaths {
    /// `POST conversations/assign`. ⚠️ Under `conversations`, a sibling of the list.
    static let conversationsAssign = conversations + ["assign"]

    /// ⛔ UNDER `workspace/whatsapp`, NOT `whatsapp`: `/api/district/whatsapp/window` is a
    /// 404. The senders, onboarding and templates routes share the prefix.
    private static let workspaceWhatsApp = workspace + ["whatsapp"]
    static let whatsAppWindow = workspaceWhatsApp + ["window"]
    static let whatsAppTemplates = workspaceWhatsApp + ["templates"]
}
