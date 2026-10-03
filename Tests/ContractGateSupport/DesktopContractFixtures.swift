import Foundation

/// Where the DESKTOP contract fixtures live: `contracts/desktop/`, the server's
/// desktop set, copied in unchanged.
///
/// ⛔ A SEPARATE SET FROM `contracts/mobile/`, WITH ITS OWN COUNT, AND IT MUST STAY
/// ONE. The server keeps desktop-only shapes out of the mobile directory because
/// that directory's count is asserted exactly by this package and by the Android
/// client; moving a file between them would red both gates for a change that is not
/// a contract change.
///
/// ⚠️ THE SAME THROWING GUARD AS ``ContractFixtures``, shared rather than copied: a
/// missing or empty directory is a failure, never a run that verified nothing.
/// (The guard's messages name `contracts/mobile/`; for this set read them as
/// `contracts/desktop/`.)
public enum DesktopContractFixtures {
    /// The environment variable that overrides the location, for a containerised
    /// run whose mount does not include the repository root. ⚠️ Blank means unset,
    /// for the reason ``ContractFixtures/directory`` gives.
    public static let overrideEnvironmentKey = "DISTRICT_DESKTOP_CONTRACTS_DIR"

    /// The resolved directory: the override, or `<repo>/contracts/desktop` walked up
    /// from this file the way ``ContractFixtures`` walks to `mobile`.
    public static var directory: URL {
        let override = ProcessInfo.processInfo.environment[overrideEnvironmentKey] ?? ""
        if override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return defaultDirectory
        }
        return URL(fileURLWithPath: override, isDirectory: true)
    }

    private static var defaultDirectory: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 3 {
            url = url.deletingLastPathComponent()
        }
        return url
            .appendingPathComponent("contracts", isDirectory: true)
            .appendingPathComponent("desktop", isDirectory: true)
    }

    /// Every `.json` fixture in the desktop set, sorted. Throws rather than
    /// returning an empty array.
    public static func allFixtureNames() throws -> [String] {
        try ContractFixtures.fixtureNames(in: directory)
    }

    /// Read one desktop fixture's bytes.
    public static func read(_ name: String) throws -> Data {
        try ContractFixtures.read(name, in: directory)
    }
}
