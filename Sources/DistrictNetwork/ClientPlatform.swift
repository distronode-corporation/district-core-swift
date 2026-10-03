import Foundation

/// Which of the two Apple clients is talking: District AI for iOS (iPhone and
/// iPad) or for macOS.
///
/// ⛔ CHOSEN ONCE, BY THE APP TARGET, AND NEVER PER REQUEST. Five places put a
/// platform on the wire (the two native sign-in exchanges, the push register,
/// its `platform` constant and the room token's `identity`), and every one of
/// them takes this type with a default of ``ios``. So the iOS app passes nothing
/// and its bytes are exactly what they were before this type existed, and the
/// macOS app passes ``macos`` at the composition root. A screen choosing the
/// value is how a device ends up listed as the wrong platform in the settings
/// device list.
///
/// ⛔ THE SERVER'S SCHEMAS ARE THE AUTHORITY ON WHAT EACH ROUTE ACCEPTS, AND THEY
/// DIFFER. `native/token` takes `ios | android | linux | macos`; `native/apple`
/// takes `ios | android | macos`; `devices/register` takes
/// `android | ios | linux | macos` and then refuses `macos` with `kind: "voip"`
/// (macOS has no PushKit ring) and `kind: "desktop"` on anything but a desktop
/// platform. Both cases here are accepted by every route this client calls, and
/// the one refused pairing is described on ``PushTokenKind``.
public enum ClientPlatform: String, Sendable, CaseIterable, Equatable {
    case ios
    case macos

    /// The value on the wire. ⚠️ The raw value, spelled out so a call site reads
    /// as "the wire value" rather than as an enum detail.
    public var wire: String {
        rawValue
    }
}
