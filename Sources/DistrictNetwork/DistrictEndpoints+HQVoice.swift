import DistrictModel
import Foundation

/// District HQ by voice: the routes the Windows and Linux apps call (core-rust
/// `district-api/src/hq.rs`), against the service's `/api/district/hq/` voice routes.
public extension DistrictEndpoints {
    /// A LiveKit credential for one voice session.
    ///
    /// ⛔ EACH CALL STARTS A BILLED SESSION: only on a member's action, never as a prefetch.
    /// ⚠️ `history` is bounded here as the service bounds it (``HQVoiceTurn/bounded(_:)``)
    /// and left out when empty. The client declares no `caps`: it renders no `hq.ui`
    /// commands, so the agent is given no screen-moving tools, as on the desktop.
    ///
    /// - Parameter locale: `fr` for French, `en` otherwise (the portal's language; the
    ///   member's voice settings may override it on the service).
    static func hqVoiceToken(workspaceId: String, locale: String, history: [HQVoiceTurn]) -> ApiRequestDescriptor {
        let turns = HQVoiceTurn.bounded(history)
        return ApiRequestDescriptor(
            .hqVoiceToken,
            .post,
            DistrictPaths.hqVoiceToken,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("locale", .string(locale == "fr" ? "fr" : "en")),
                ("history", turns.isEmpty ? nil : .array(turns.map { turn in
                    .object([("role", .string(turn.role.rawValue)), ("text", .string(turn.text))])
                })),
            ]))
        )
    }

    /// What is on the member's screen, for the voice agent. Fire and forget: the next
    /// report replaces a lost one.
    static func hqVoiceContext(workspaceId: String, roomName: String, screen: HQVoiceScreen) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .hqVoiceContext,
            .post,
            DistrictPaths.hqVoiceContext,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("roomName", .string(roomName)),
                ("snapshot", .object([
                    ("version", .integer(screen.version)),
                    ("page", .string(screen.page.id)),
                    ("selected", screen.selected.map { selected in
                        .object([("kind", .string(selected.kind.rawValue)), ("id", .string(selected.id))])
                    }),
                ])),
            ]))
        )
    }

    /// The member's own voice settings in a workspace (the defaults when none are saved).
    static func hqVoiceSettings(workspaceId: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .hqVoiceSettings,
            .get,
            DistrictPaths.hqVoiceSettings,
            query: [ApiQueryItem("workspaceId", workspaceId)]
        )
    }

    /// Saves the member's voice settings and answers them as stored.
    static func saveHqVoiceSettings(workspaceId: String, settings: HQVoiceSettings) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .saveHqVoiceSettings,
            .put,
            DistrictPaths.hqVoiceSettings,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("settings", .object([
                    ("voice", .string(settings.voice)),
                    ("length", .string(settings.length)),
                    ("pace", .string(settings.pace)),
                    ("language", .string(settings.language)),
                    ("micMode", .string(settings.micMode)),
                ])),
            ]))
        )
    }

    /// Cancels a proposal the voice agent made, by a click.
    static func hqProposalCancel(workspaceId: String, proposalId: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .hqProposalCancel,
            .post,
            DistrictPaths.hqProposalCancel,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("proposalId", .string(proposalId)),
            ]))
        )
    }
}
