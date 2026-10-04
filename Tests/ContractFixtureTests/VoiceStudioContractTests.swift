import ContractGateSupport
import DistrictModel
import Foundation
import XCTest

/// `district-voice-studio.json`: the rows the Studio's rules lean on, and the field-level null
/// permission proved able to fail.
final class VoiceStudioContractTests: XCTestCase {
    private func studio() throws -> VoiceStudioResponse {
        try StrictDecodeVerifier.verify(
            name: VoiceStudioNulls.fixture,
            json: ContractFixtures.read(VoiceStudioNulls.fixture),
            as: VoiceStudioResponse.self,
            allowingExplicitNulls: VoiceStudioNulls.permitted(in: ContractFixtures.read(VoiceStudioNulls.fixture))
        )
    }

    /// ⛔ A CHAIN CARRIES A MIX AND NO REALTIME MODEL, A REALTIME ENGINE THE REVERSE, ON EVERY
    /// CHAIN IN THE FILE. `VoiceStudioEngine(chain:)` reads the kind off the mix alone.
    func testEveryChainCarriesExactlyOneOfAMixAndARealtimeModel() throws {
        let studio = try studio()
        for chain in [studio.current.chain] + studio.recipes.map(\.chain) {
            switch chain.kind {
            case "chained":
                XCTAssertNotNil(chain.engineMix)
                XCTAssertNil(chain.realtimeModelId)
                XCTAssertEqual(chain.blocks.map(\.leg), ["stt", "turn", "llm", "tts"])
            default:
                XCTAssertEqual(chain.kind, "realtime")
                XCTAssertNil(chain.engineMix)
                XCTAssertNotNil(chain.realtimeModelId)
                XCTAssertEqual(chain.blocks.map(\.leg), ["realtime"])
            }
        }
    }

    /// ⚠️ THE ABSENT-WHEN-UNSET MIX KEYS ARE ABSENT IN EVERY MIX THE FILE CARRIES, which is
    /// exactly the shape a non-optional property would fail to decode.
    func testNoMixInTheFileCarriesATuningKey() throws {
        let studio = try studio()
        let mixes = studio.catalog.presets.map(\.engineMix) + studio.recipes.compactMap(\.chain.engineMix)
        XCTAssertFalse(mixes.isEmpty)
        for mix in mixes {
            XCTAssertNil(mix.stt.keyterms)
            XCTAssertNil(mix.turn.interruption)
            XCTAssertEqual(mix.version, 1)
        }
    }

    /// The saved persona is the Fastest recipe, so its save body is the tile's.
    func testTheSavedPersonaIsTheTileItMatches() throws {
        let studio = try studio()
        let tile = try XCTUnwrap(
            studio.recipes.first { $0.id == studio.current.recipeId && $0.tier == studio.current.tier }
        )
        XCTAssertEqual(tile.save, studio.current.fields)
        XCTAssertEqual(tile.chain, studio.current.chain)
    }

    /// ⛔ THE LABELS ARE THE SERVICE'S, IN ITS LOCALE, and the wire values never are.
    func testTheLabelsAreLocalizedAndTheValuesAreNot() throws {
        let studio = try studio()
        XCTAssertEqual(studio.locale, "en")
        XCTAssertEqual(studio.labels.stages.llmTtft, "Brain, first word")
        XCTAssertEqual(studio.latency.stages.map(\.stage), ["eou", "llm_ttft", "tts_ttfb"])
        XCTAssertTrue(studio.voices.filter { $0.kind == "realtime" }.allSatisfy(\.provider.isEmpty))
    }

    // MARK: - The permission proved able to fail

    func testANullInAFieldNoEntryNamesFailsTheGate() throws {
        let data = Data(#"{"region":null}"#.utf8)
        XCTAssertThrowsError(try VoiceStudioNulls.permitted(in: data)) { error in
            XCTAssertTrue(error is VoiceStudioNulls.Unpermitted)
            XCTAssertTrue(String(describing: error).contains("$.region"))
        }
    }

    /// ⛔ A PERMISSION NOBODY USES IS A PERMISSION NOBODY CHECKED.
    func testAPermittedFieldThatHoldsNoNullFailsTheGate() throws {
        let data = Data(#"{"latency":{"note":null}}"#.utf8)
        XCTAssertThrowsError(try VoiceStudioNulls.permitted(in: data)) { error in
            XCTAssertTrue(error is VoiceStudioNulls.Unused)
            XCTAssertTrue(String(describing: error).contains("$.voices[*].groups[*].options[*].p50"))
        }
    }

    func testAPathsKindReplacesEveryIndexAndNoKey() {
        XCTAssertEqual(
            VoiceStudioNulls.kind(of: "$.voices[3].groups[0].options[17].p50"),
            "$.voices[*].groups[*].options[*].p50"
        )
        XCTAssertEqual(VoiceStudioNulls.kind(of: "$.latency.note"), "$.latency.note")
    }
}
