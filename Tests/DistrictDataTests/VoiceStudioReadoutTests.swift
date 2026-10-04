@testable import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// What the chain strip, the meter and the residency summary say: the service's own words when
/// it has described the held engine, an assembly of its per-leg facts when it has not, and never
/// an estimate.
final class VoiceStudioReadoutTests: XCTestCase {
    private typealias Readout = VoiceStudioReadout
    private typealias Local = VoiceStudioLocalReadout

    private var flux: VoiceStudioEngine {
        .chained(VoiceStudioFixture.fluxChain)
    }

    // MARK: - The service's own words

    func testTheSavedEngineIsDescribedInTheServicesWords() throws {
        let studio = try VoiceStudioFixture.response()
        let blocks = Readout.blocks(flux, in: studio)
        XCTAssertEqual(blocks.map(\.title), ["Ear", "Turn-taking", "Brain", "Voice"])
        XCTAssertEqual(blocks.first?.latency, .server(studio.current.chain.blocks[0].latency?.text ?? ""))
        XCTAssertEqual(blocks.first?.place, studio.current.chain.blocks[0].where)
        let meter = Readout.meter(flux, in: studio)
        XCTAssertEqual(meter.headline, .server(studio.latency.text))
        XCTAssertEqual(meter.stages.count, studio.latency.stages.count)
        XCTAssertEqual(Readout.residency(flux, in: studio).text, studio.current.chain.residency.text)
    }

    func testARecipesEngineIsDescribedInItsTilesWords() throws {
        let studio = try VoiceStudioFixture.response()
        let natural = try XCTUnwrap(studio.recipes.first { $0.id == "natural" && $0.tier == "stable" })
        let engine = VoiceStudioEngine(chain: natural.chain)
        XCTAssertEqual(Readout.meter(engine, in: studio).headline, .server(natural.timeToFirstWord.text))
        XCTAssertEqual(Readout.meter(engine, in: studio).note, natural.timeToFirstWord.note)
        XCTAssertEqual(Readout.blocks(engine, in: studio).map(\.model), natural.chain.blocks.map(\.model))
        XCTAssertEqual(Readout.residency(engine, in: studio).legsOut, natural.chain.residency.legsOut)
    }

    // MARK: - An unsaved edit

    /// ⛔ ASSEMBLED FROM THE SAME RESPONSE'S MEDIANS: end of turn, the brain at its own region
    /// with thinking off, and the mouth.
    func testAnUnsavedChainSumsTheMeasuredMedians() throws {
        let studio = try VoiceStudioFixture.response()
        let edited = flux.withVoice("aura-2-luna-en")
        let fixed = try VoiceStudioFixture.response {
            try $0.editEntry(["voices"], where: ["model": "aura-2"]) { list in
                try list.edit(["groups"]) { groups in
                    guard case var .array(rows) = groups, case var .object(first) = rows[0],
                          case var .array(options) = first["options"] ?? .null, case var .object(luna) = options[1]
                    else { throw FixtureEditFailed(path: ["groups"]) }
                    luna["p50"] = .integer(90)
                    options[1] = .object(luna)
                    first["options"] = .array(options)
                    rows[0] = .object(first)
                    groups = .array(rows)
                }
            }
        }
        // Luna has no measured median of its own in the fixture: the mouth is missing.
        let missing = Readout.meter(edited, in: studio)
        XCTAssertEqual(missing.headline, .local(ms: 850, atLeast: true))
        XCTAssertNotNil(missing.note)
        XCTAssertEqual(missing.stages.last?.value, VoiceStudioLatencyText.none)

        let measured = Readout.meter(edited, in: fixed)
        XCTAssertEqual(measured.headline, .local(ms: 940, atLeast: false))
        XCTAssertNil(measured.note)
        XCTAssertEqual(measured.stages.last?.value, .milliseconds(90))
        XCTAssertEqual(Readout.blocks(edited, in: fixed).last?.latency, .milliseconds(90))
        XCTAssertEqual(Readout.blocks(edited, in: studio).last?.latency, VoiceStudioLatencyText.none)
    }

    /// ⛔ THE BRAIN'S MEDIAN COUNTS ONLY WHERE IT WAS MEASURED: thinking off, at the region's own
    /// location. Anywhere else the stage is missing and the meter says "at least".
    func testABrainAwayFromItsMeasuredSettingIsAMissingStage() throws {
        let studio = try VoiceStudioFixture.response()
        var thinking = VoiceStudioFixture.fluxChain
        thinking.llm.thinking = "dynamic"
        XCTAssertEqual(Readout.meter(.chained(thinking), in: studio).headline, .local(ms: 520, atLeast: true))
        XCTAssertEqual(Readout.blocks(.chained(thinking), in: studio)[2].latency, VoiceStudioLatencyText.none)

        var east = VoiceStudioFixture.fluxChain
        east.llm.location = "us-east4"
        XCTAssertEqual(Readout.meter(.chained(east), in: studio).headline, .local(ms: 970, atLeast: false))
    }

    func testTheBrainIsLocalOnlyAtItsRegionsOwnLocation() throws {
        let studio = try VoiceStudioFixture.response()
        let flash25 = try XCTUnwrap(studio.catalog.llm.first { $0.model == "gemini-2.5-flash" })
        let flash35 = try XCTUnwrap(studio.catalog.llm.first { $0.model == "gemini-3.5-flash" })
        var mix = VoiceStudioFixture.fluxChain
        XCTAssertTrue(Local.brainLocal(mix, flash25))
        mix.llm.location = "us-east4"
        XCTAssertTrue(Local.brainLocal(mix, flash25))
        mix.llm.location = "northamerica-northeast1"
        XCTAssertFalse(Local.brainLocal(mix, flash25))
        // ⚠️ A brain the region does not serve has no `auto` to be local to.
        XCTAssertFalse(Local.brainLocal(mix, flash35))
        mix.llm.thinking = "dynamic"
        mix.llm.location = "auto"
        XCTAssertFalse(Local.brainLocal(mix, flash25))
    }

    /// The Turn-taking block is the ear's own for Flux, and the agent's detector otherwise.
    func testTurnTakingIsFluxsOwnOrTheAgentsDetector() throws {
        let studio = try VoiceStudioFixture.response()
        var tuned = VoiceStudioFixture.fluxChain
        tuned.turn.minDelay = 0.4
        let fluxTurn = Readout.blocks(.chained(tuned), in: studio)[1]
        XCTAssertEqual(fluxTurn.model, studio.catalog.turn.ear.label)
        XCTAssertEqual(fluxTurn.inRegion, true)
        XCTAssertEqual(fluxTurn.role, "When to reply")

        tuned.stt.model = "nova-3-general"
        let detector = Readout.blocks(.chained(tuned), in: studio)[1]
        XCTAssertEqual(detector.model, studio.catalog.turn.detector.label)
        XCTAssertEqual(detector.place, studio.catalog.turn.detector.where)
        XCTAssertNil(detector.inRegion)
        XCTAssertEqual(detector.channelLabel, studio.labels.channels.stable)
    }

    /// ⛔ A LEG THAT LEAVES THE REGION IS NAMED, WITH WHERE IT GOES.
    func testAnUnsavedChainLeavingTheRegionSaysWhichLeg() throws {
        let studio = try VoiceStudioFixture.response()
        var abroad = VoiceStudioFixture.fluxChain
        abroad.llm.location = "europe-west4"
        let residency = Readout.residency(.chained(abroad), in: studio)
        XCTAssertFalse(residency.inRegion)
        XCTAssertEqual(residency.text, studio.labels.leavesRegion)
        XCTAssertEqual(residency.legsOut.count, 1)
        XCTAssertTrue(residency.legsOut[0].hasPrefix(studio.labels.legs.llm + ": "))

        var home = VoiceStudioFixture.fluxChain
        home.llm.temperature = 1.1
        let inRegion = Readout.residency(.chained(home), in: studio)
        XCTAssertTrue(inRegion.inRegion)
        XCTAssertEqual(inRegion.text, studio.labels.allInRegion)
    }

    /// ⛔ AN ENGINE NOTHING CAN DESCRIBE IS NOT CLAIMED TO STAY IN REGION.
    func testAnEngineTheCatalogueCannotDescribeClaimsNothing() throws {
        let studio = try VoiceStudioFixture.response()
        var unknown = VoiceStudioFixture.fluxChain
        unknown.stt.model = "nope"
        XCTAssertEqual(Readout.blocks(.chained(unknown), in: studio), [])
        let residency = Readout.residency(.chained(unknown), in: studio)
        XCTAssertFalse(residency.inRegion)
        XCTAssertEqual(residency.legsOut, [])
        XCTAssertEqual(Readout.meter(.chained(unknown), in: studio).headline, .local(ms: 400, atLeast: true))

        let gone = VoiceStudioEngine.realtime(modelId: "nope", voice: "Puck")
        XCTAssertEqual(Readout.blocks(gone, in: studio), [])
        XCTAssertFalse(Readout.residency(gone, in: studio).inRegion)
        XCTAssertEqual(Readout.meter(gone, in: studio).headline, VoiceStudioMeterHeadline.none)
    }

    /// ⛔ A REALTIME METER IS ALWAYS "AT LEAST": end of turn is never measured for it.
    func testAnUnsavedRealtimeEngineIsAtLeastItsModel() throws {
        let studio = try VoiceStudioFixture.response { document in
            try document.editEntry(["recipes"], where: ["id": "realtime", "tier": "stable"]) {
                try $0.edit(["chain", "voice"]) { $0 = .string("Charon") }
            }
        }
        let live = VoiceStudioEngine.realtime(modelId: VoiceStudioRules.geminiLive25, voice: "Kore")
        let meter = Readout.meter(live, in: studio)
        XCTAssertEqual(meter.headline, .local(ms: 300, atLeast: true))
        XCTAssertEqual(meter.stages.first?.value, VoiceStudioLatencyText.none)
        let block = try XCTUnwrap(Readout.blocks(live, in: studio).first)
        XCTAssertEqual(block.title, "All-in-one")
        XCTAssertEqual(block.leg, VoiceStudioLeg.realtime.rawValue)
        XCTAssertTrue(Readout.residency(live, in: studio).inRegion)

        let preview = VoiceStudioEngine.realtime(modelId: VoiceStudioRules.gemini38Live, voice: "Kore")
        let abroad = Readout.residency(preview, in: studio)
        XCTAssertFalse(abroad.inRegion)
        XCTAssertTrue(abroad.legsOut[0].hasPrefix("All-in-one: "))
        XCTAssertEqual(Readout.meter(preview, in: studio).headline, VoiceStudioMeterHeadline.none)
        XCTAssertEqual(Readout.blocks(preview, in: studio).first?.note, "Preview: processed globally by Google")
    }

    // MARK: - Small pieces

    func testAStageSaysTheServicesSentenceOrTheBareNumber() {
        XCTAssertEqual(Local.stageText(nil), VoiceStudioLatencyText.none)
        let bare = VoiceStudioLatency(source: VoiceStudioLatency.measuredSource, ms: 90, samples: nil, text: "")
        XCTAssertEqual(Local.stageText(bare), .milliseconds(90))
        let said = VoiceStudioLatency(source: "lab", ms: 90, samples: nil, text: "Lab: 90 ms")
        XCTAssertEqual(Local.stageText(said), .server("Lab: 90 ms"))
        XCTAssertFalse(said.isMeasured)
        XCTAssertEqual(VoiceStudioLatencyText(said), .server("Lab: 90 ms"))
        XCTAssertEqual(VoiceStudioLatencyText(nil), VoiceStudioLatencyText.none)
    }

    /// Another vendor's mouth uses its model's number, measured or not; a lab probe is no median.
    func testAnotherVendorsMouthUsesItsModelsNumber() throws {
        let studio = try VoiceStudioFixture.response()
        var sonic = VoiceStudioFixture.fluxChain
        sonic.tts = EngineMixTts(provider: "cartesia", model: "sonic-3", voice: "47c38ca4-5f35-497b-b1a3-415245fb35e1")
        let mouth = try XCTUnwrap(studio.catalog.tts.first { $0.model == "sonic-3" })
        XCTAssertNil(Local.mouthMeasured(sonic, mouth, in: studio))
        XCTAssertEqual(Local.mouthText(sonic, mouth, in: studio), VoiceStudioLatencyText(mouth.latency))
    }
}
