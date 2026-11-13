@testable import DistrictNetwork
import Foundation
import XCTest

/// `calls/outbound` is the AI campaign launcher, and it has exactly one way in.
///
/// ⛔ THE ROUTE WAS UNREACHABLE UNTIL A DEDICATED LAUNCHER WAS DECIDED ON, AND THIS IS WHAT
/// KEEPS IT DEDICATED. It creates a `call_` room the voice agent joins and speaks in, so a
/// person who dialled through it would find the agent on their own line. One
/// ``EndpointID`` addresses it, that ID belongs to the campaigns family and not the
/// softphone's, and `CampaignsRepository` is the only repository that names it.
final class EndpointCampaignGuardTests: XCTestCase {
    private static let outbound = ["api", "district", "calls", "outbound"]

    /// What naming the launcher looks like in source: its ID or builder, the repository
    /// method, or the path segment spelled as a segment list (a bare `"outbound"` is also a
    /// call direction, so it is not one of these).
    private static let launcherTokens = ["aiCampaignLaunch", "launchAICampaign", #"["outbound"]"#]

    /// Exactly one row on the whole expressible surface addresses `calls/outbound`, and it
    /// is ``EndpointID/aiCampaignLaunch``.
    func testExactlyOneEndpointAddressesTheCampaignLauncher() {
        let rows = EndpointTable.all().filter { $0.descriptor.segments.contains("outbound") }
        XCTAssertEqual(rows.map(\.id), [.aiCampaignLaunch])
        XCTAssertEqual(rows.map(\.descriptor.segments), [Self.outbound])
        XCTAssertEqual(DistrictPaths.aiCampaignLaunch, Self.outbound)
        XCTAssertNil(EndpointID(rawValue: "callsOutbound"), "a second name for the launcher")

        XCTAssertTrue(TypedEndpoints.campaigns.contains(.aiCampaignLaunch))
        XCTAssertFalse(TypedEndpoints.softphone.contains(.aiCampaignLaunch))

        // The routes under `calls/` a person dials and answers through, so the filter
        // above is not passing merely because the family is empty.
        XCTAssertEqual(DistrictPaths.callsDial, ["api", "district", "calls", "dial"])
        XCTAssertEqual(DistrictPaths.callsToken, ["api", "district", "calls", "token"])
        XCTAssertEqual(
            DistrictPaths.callAnswer("call_1"),
            ["api", "district", "calls", "call_1", "answer"]
        )
    }

    /// ⛔ NO OTHER REPOSITORY, AND NOTHING SOFTPHONE-RELATED, NAMES THE LAUNCHER. Read off
    /// the sources themselves: outside `DistrictNetwork`, which declares it, the builder and
    /// the repository method appear in `CampaignsRepository.swift` and nowhere else.
    ///
    /// ⚠️ `DistrictCall` (the softphone) cannot import `DistrictNetwork` at all, so this
    /// scan is the guard for `DistrictData` and `DistrictLive`.
    func testOnlyTheCampaignsRepositoryNamesTheLauncher() throws {
        let sources = Self.sourcesDirectory()
        let files = try Self.swiftFiles(under: sources)
        XCTAssertGreaterThan(files.count, 100, "the source walk found no sources at \(sources.path)")

        var naming: Set<String> = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let relative = String(file.path.dropFirst(sources.path.count + 1))
            if Self.launcherTokens.contains(where: text.contains) {
                naming.insert(relative)
            }
        }
        let outsideNetwork = naming.filter { !$0.hasPrefix("DistrictNetwork/") }
        XCTAssertEqual(outsideNetwork, ["DistrictData/CampaignsRepository.swift"])
        XCTAssertEqual(naming.subtracting(outsideNetwork), [
            "DistrictNetwork/DistrictEndpoints+Campaigns.swift",
            "DistrictNetwork/DistrictPaths.swift",
            "DistrictNetwork/EndpointClassification+Campaigns.swift",
            "DistrictNetwork/EndpointID.swift",
        ])
    }

    /// `<repo>/Sources`, walked up from this file: this file, `DistrictNetworkTests`,
    /// `Tests`.
    private static func sourcesDirectory() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 3 {
            url = url.deletingLastPathComponent()
        }
        return url.appendingPathComponent("Sources", isDirectory: true).standardizedFileURL
    }

    private static func swiftFiles(under directory: URL) throws -> [URL] {
        let walker = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map(\.standardizedFileURL)
    }
}
