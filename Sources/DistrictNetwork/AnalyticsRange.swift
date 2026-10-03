import Foundation

/// The analytics window, as an enum rather than a string.
///
/// ⛔ AN UNRECOGNISED `timeRange` IS NOT AN ERROR SERVER-SIDE, the route
/// silently falls back to 7d and answers **200**. So a wrong value serves a
/// week's figures under whatever heading the UI is showing, with nothing anywhere
/// reporting a problem. ``wire`` is the only thing standing between this client
/// and that outcome, which is why the range is a type on the signature and not a
/// `String`.
///
/// ⚠️ THE RESPONSE SIZE DEPENDS ON THE WINDOW. 7d and 30d bucket DAILY; 90d
/// buckets WEEKLY. A caller sizing a chart from a constant will be wrong for two
/// of the three.
public enum AnalyticsRange: Sendable, CaseIterable {
    case sevenDays
    case thirtyDays
    case ninetyDays

    /// ⛔ THE WIRE VALUE, NEVER THE CASE NAME. `sevenDays` sent literally would
    /// be unrecognised, and unrecognised means "a silent week of data".
    public var wire: String {
        switch self {
        case .sevenDays: "7d"
        case .thirtyDays: "30d"
        case .ninetyDays: "90d"
        }
    }
}

/// The `platform` value this client may send when registering for push.
///
/// ⚠️ SENT EXPLICITLY EVEN THOUGH THE SERVER DEFAULTS IT. The column is NOT NULL
/// and the route's zod schema defaults the field to `"android"`, so omitting it
/// works, and would label every iOS row as an Android one, which is the row the
/// server's push sender selects an APNs payload from.
///
/// ⚠️ THE VALUE SENT IS ``ClientPlatform/wire``. These constants name the two
/// values for assertions and for readers; the register descriptor takes a
/// ``ClientPlatform`` so a third spelling cannot reach the wire.
public enum PushPlatform {
    public static let ios = ClientPlatform.ios.wire
    /// ⚠️ A macOS row is APNs like an iOS one: the server's fan-out sends a
    /// `macos` alert row exactly the way it sends an iOS alert row.
    public static let macos = ClientPlatform.macos.wire
}

/// Which of this installation's TWO push tokens is being registered.
///
/// ⛔ TWO TOKENS FOR ONE HANDSET, NOT ONE TOKEN WITH TWO USES, AND THAT IS THE
/// WHOLE REASON THIS TYPE EXISTS. APNs issues the alert token to
/// `UIApplication.registerForRemoteNotifications()` and PushKit issues an
/// entirely separate one to `PKPushRegistry`; a VoIP payload sent to the alert
/// token is rejected and an alert sent to the VoIP token is not delivered.
/// Registering one over the other on a route whose upsert key is the
/// INSTALLATION is how a device ends up reachable by neither.
///
/// ⚠️ ``alert`` OMITS THE KEY RATHER THAN SENDING `"fcm"`, WHICH IS THE OPPOSITE
/// CALL FROM THE ONE ``PushPlatform`` MAKES, AND THE DIFFERENCE IS WHETHER THE
/// SERVER'S DEFAULT IS RIGHT. `platform` defaults to `"android"`, which is wrong
/// for every row this client writes; `kind` defaults to `"fcm"`, which is
/// exactly what the alert token is. So the alert register's bytes are unchanged
/// by this type and only the VoIP one grew a key.
/// ⛔ THAT HOLDS ONLY WHILE THE SERVER DEFAULTS IT. If the server ever makes `kind`
/// a REQUIRED field rather than a defaulted one, the alert register starts
/// answering 400 and the fix is to give ``alert`` a wire value of `"fcm"` here.
///
/// ⛔ ``desktop`` IS NOT A TOKEN AT ALL, IT IS PRESENCE, AND THE SERVER ACCEPTS IT
/// ONLY FROM A DESKTOP PLATFORM. A Mac has no PushKit ring, so it is rung over the
/// live telemetry socket instead, and only while its `desktop` row is under ten
/// minutes old (`DESKTOP_PRESENCE_FRESH_MS`). The row's `token` is an opaque
/// install nonce the server never sends anything to. `devices/register` answers
/// 400 for `desktop` with platform `ios`, and for `voip` with platform `macos`, so
/// the only pairs that land are: iOS `alert` and `voip`, macOS `alert` and
/// `desktop`. See `DistrictLive.PresenceController`, which is the one caller of
/// ``desktop``.
public enum PushTokenKind: Sendable, CaseIterable {
    /// The APNs device token, for notifications the user sees.
    case alert
    /// The PushKit token, for the ring that wakes the app. See `VoIPPushHandler`.
    case voip
    /// A Mac's presence: "a call may ring this desktop". See the ⛔ on the type.
    case desktop

    /// The value to put on the wire, or nil to leave the key out entirely.
    var wire: String? {
        switch self {
        case .alert: nil
        case .voip: "voip"
        case .desktop: "desktop"
        }
    }
}
