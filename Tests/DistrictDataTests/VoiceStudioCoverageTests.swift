@testable import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// The fallbacks the main suites never reach, each with the input that reaches it.
///
/// ⚠️ llvm-cov COUNTS THE RIGHT-HAND SIDE OF `??` AS ITS OWN REGION (see
/// `ci/coverage-gate.sh`), so every fallback here is a line the gate holds us to.
final class VoiceStudioCoverageTests: XCTestCase {
    /// ⛔ AN END-OF-TURN NUMBER FROM A LAB PROBE IS NOT A MEDIAN: the stage is missing.
    func testALabEndOfTurnIsAMissingStage() throws {
        let studio = try VoiceStudioFixture.response {
            try $0.edit(["latency", "eou", "source"]) { $0 = .string("lab") }
        }
        var edited = VoiceStudioFixture.fluxChain
        edited.llm.temperature = 1.1
        XCTAssertEqual(
            VoiceStudioReadout.meter(.chained(edited), in: studio).headline,
            .local(ms: 570, atLeast: true)
        )
    }

    /// With no realtime block anywhere in the response, a realtime engine's block is titled
    /// by its model and has no role.
    func testARealtimeEngineWithNoServerBlockIsTitledByItsModel() throws {
        let studio = try VoiceStudioFixture.response {
            try $0.edit(["recipes"]) { recipes in
                guard case let .array(rows) = recipes else { return }
                recipes = .array(rows.filter { $0["chain"]?["kind"]?.stringValue != "realtime" })
            }
        }
        let engine = VoiceStudioEngine.realtime(modelId: VoiceStudioRules.geminiLive25, voice: "Kore")
        let block = try XCTUnwrap(VoiceStudioReadout.blocks(engine, in: studio).first)
        XCTAssertEqual(block.title, "Gemini 2.5 Live (native audio)")
        XCTAssertEqual(block.role, "")
    }

    func testALegWhoseModelTheCatalogueLacksHasNoLocations() throws {
        let studio = try VoiceStudioFixture.response()
        var unknown = VoiceStudioFixture.fluxChain
        unknown.stt.model = "nope"
        unknown.llm.model = "nope"
        unknown.tts.model = "nope"
        for leg in [VoiceStudioLeg.stt, .llm, .tts] {
            XCTAssertEqual(VoiceStudioPickers.locations(for: leg, mix: unknown, in: studio), [], leg.rawValue)
        }
    }

    func testNoListHasNoVoice() {
        XCTAssertNil(VoiceStudioRecipes.voiceOption("Puck", in: nil))
    }

    func testAContinuousSliderIsNotWhole() {
        XCTAssertFalse(VoiceStudioTuningRange(min: 0, max: 1, step: nil, start: 0, useDefaultLabel: nil).isWhole)
    }
}
