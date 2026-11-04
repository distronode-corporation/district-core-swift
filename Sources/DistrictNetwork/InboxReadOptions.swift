import Foundation

/// What this build asks the Inbox reads for, beyond the shape every installed build gets.
///
/// ⛔ BOTH ARE OPT-IN ON THE WIRE, AND THAT IS THE SERVER'S COMPATIBILITY STORY. Without
/// `metaChannels=1` and `assignments=1` the four reads answer byte for byte what they did
/// before either existed, which is what every installed app decodes.
///
/// ⚠️ CHOSEN ONCE, AT THE COMPOSITION ROOT, like ``ClientPlatform``: one ``InboxReadOptions``
/// is handed to the Inbox repository and every read it makes carries the same answer. A
/// list that showed Messenger threads while the thread read refused them (an installed
/// build gets 404 for a Meta message) is the bug a per-call choice would allow.
public struct InboxReadOptions: Sendable, Equatable {
    /// Send `metaChannels=1` on `conversations`, `timeline`, `messages/{id}` and
    /// `messages/unread-count`: the list includes Messenger and Instagram threads and each
    /// row carries `replyOptions`, the timeline carries `messenger` and `instagram` rows,
    /// the resolver answers for a Meta message, and the badge counts them.
    ///
    /// ⚠️ ON BY DEFAULT: a build linking this version renders replies through
    /// `ConversationSummary.replyTargets`, which reads `replyOptions` first.
    public var metaChannels: Bool
    /// Send `assignments=1` on `conversations`: each row carries `assigneeEmail` and
    /// `assignedToMe`. Off by default; a build turns it on with the screen that shows it.
    public var assignments: Bool

    public init(metaChannels: Bool = true, assignments: Bool = false) {
        self.metaChannels = metaChannels
        self.assignments = assignments
    }

    /// Neither flag: the requests an installed build makes, byte for byte.
    public static let legacy = InboxReadOptions(metaChannels: false, assignments: false)

    /// `"1"` when on, nil (the parameter is DROPPED, never sent as `0`) when off.
    static func flag(_ on: Bool) -> String? {
        on ? "1" : nil
    }
}

/// Something this installation declares it can open, sent with its push registration
/// (`capabilities` on `devices/register`) so the server pushes it only what it can show.
///
/// ⚠️ A STRUCT OF CONSTANTS, NOT AN ENUM, so a capability added later is not a source
/// break for a caller switching over it. The server drops any value it does not know.
public struct DeviceCapability: RawRepresentable, Hashable, Sendable, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The build lists Messenger and Instagram threads and opens them, so it may be pushed
    /// for one. ⛔ Declare it only together with ``InboxReadOptions/metaChannels``: the
    /// push opens `messages/{id}`, which answers 404 for a Meta message without that flag.
    public static let metaChannels = DeviceCapability(rawValue: "metaChannels")

    public static func < (lhs: DeviceCapability, rhs: DeviceCapability) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
