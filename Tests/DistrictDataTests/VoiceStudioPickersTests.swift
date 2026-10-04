@testable import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// What each leg's pickers offer: the web's rule, over the service's lists.
final class VoiceStudioPickersTests: XCTestCase {
    private typealias Pickers = VoiceStudioPickers

    func testAnOptionSaysItsChannelAndNoteInText() {
        let option = VoiceStudioPickerOption(value: "m", label: "Model", channelLabel: "Latest", note: "Preview note")
        XCTAssertEqual(option.id, "m")
        XCTAssertEqual(option.text, "Model · Latest · Preview note")
        XCTAssertEqual(VoiceStudioPickerOption(value: "v", label: "Vendor").text, "Vendor")
    }

    /// ⚠️ A held value the list no longer carries is still shown, as itself.
    func testAClosedPickerShowsTheHeldOptionOrTheHeldValue() {
        let options = [VoiceStudioPickerOption(value: "a", label: "Alpha")]
        XCTAssertEqual(VoiceStudioPickerOption.summary(of: options, selected: "a"), "Alpha")
        XCTAssertEqual(VoiceStudioPickerOption.summary(of: options, selected: "gone"), "gone")
        XCTAssertEqual(VoiceStudioPickerOption.summary(of: options, selected: nil), "")
    }

    /// ⛔ A VENDOR APPEARS ONCE, AND ONLY WHEN ONE OF ITS MODELS IS LISTABLE. Inworld's ear is
    /// not offered here, so the vendor is not either.
    func testEarVendorsAreTheListableOnesOnce() throws {
        let studio = try VoiceStudioFixture.response()
        let vendors = Pickers.earVendors(VoiceStudioFixture.fluxChain, bilingual: false, in: studio).map(\.value)
        XCTAssertEqual(vendors, ["deepgram", "assemblyai", "aws-transcribe", "google-stt"])
    }

    /// ⛔ THE HELD MODEL IS LISTED EVEN WHEN IT WOULD NOT BE OFFERED, so a stored choice still
    /// shows as selected.
    func testTheHeldEarIsListedEvenWhenNotOffered() throws {
        let studio = try VoiceStudioFixture.response()
        var mix = VoiceStudioFixture.fluxChain
        mix.stt = EngineMixStt(provider: "inworld", model: "inworld/inworld-stt-1")
        XCTAssertTrue(Pickers.earVendors(mix, bilingual: false, in: studio).map(\.value).contains("inworld"))
        XCTAssertEqual(Pickers.earModels(mix, bilingual: false, in: studio).map(\.value), ["inworld/inworld-stt-1"])
    }

    func testBilingualEarModelsAreTheOnesProvenOnBoth() throws {
        let studio = try VoiceStudioFixture.response()
        var nova = VoiceStudioFixture.fluxChain
        nova.stt.model = "nova-3-general"
        let models = Pickers.earModels(nova, bilingual: true, in: studio)
        XCTAssertEqual(models.map(\.value), ["nova-3-general", "flux-general-multi"])
        XCTAssertEqual(models.last?.channelLabel, "Latest")
        XCTAssertNil(models.last?.note)
    }

    func testBrainsAreTheOfferedOnesWithAPreviewNoteOnlyOnPreview() throws {
        let studio = try VoiceStudioFixture.response {
            try $0.editEntry(["catalog", "llm"], where: ["model": "gemini-3.8-flash"]) { model in
                try model.set("channel", .string("preview"))
                try model.set("offered", .bool(false))
            }
        }
        let held = Pickers.brainModels(VoiceStudioFixture.fluxChain, in: studio)
        XCTAssertEqual(held.map(\.value), ["gemini-2.5-flash", "gemini-3.5-flash", "gemini-3.6-flash"])
        var mix = VoiceStudioFixture.fluxChain
        mix.llm.model = "gemini-3.8-flash"
        XCTAssertEqual(Pickers.brainModels(mix, in: studio).last?.note, studio.labels.previewNote)
    }

    func testMouthVendorsAndModelsFollowTheLanguage() throws {
        let studio = try VoiceStudioFixture.response()
        let mix = VoiceStudioFixture.fluxChain
        XCTAssertEqual(
            Pickers.voiceVendors(mix, bilingual: false, in: studio).map(\.value),
            ["deepgram", "cartesia", "aws-polly", "google-tts"]
        )
        XCTAssertEqual(Pickers.voiceModels(mix, bilingual: false, in: studio).map(\.value), ["aura-2", "flux-tts"])
        // ⚠️ Bilingual keeps the held mouth listed and offers nothing else from Deepgram.
        XCTAssertEqual(Pickers.voiceModels(mix, bilingual: true, in: studio).map(\.value), ["aura-2"])
    }

    func testLocationsAreTheHeldModelsOwn() throws {
        let studio = try VoiceStudioFixture.response()
        var mix = VoiceStudioFixture.fluxChain
        XCTAssertEqual(Pickers.locations(for: .stt, mix: mix, in: studio), [])
        XCTAssertEqual(Pickers.locations(for: .llm, mix: mix, in: studio).first?.value, "auto")
        XCTAssertEqual(Pickers.locations(for: .turn, mix: mix, in: studio), [])
        XCTAssertEqual(Pickers.locations(for: .realtime, mix: mix, in: studio), [])
        mix.stt = EngineMixStt(provider: "google-stt", model: "chirp_3", location: "eu")
        mix.tts = EngineMixTts(provider: "google-tts", model: "chirp-3-hd", voice: "Achernar")
        XCTAssertEqual(Pickers.locations(for: .stt, mix: mix, in: studio).map(\.value), ["us", "eu"])
        let mouth = Pickers.locations(for: .tts, mix: mix, in: studio)
        XCTAssertEqual(mouth.map(\.value), ["global", "us", "eu", "asia-southeast1"])

        // ⚠️ An unset location shows the list's first entry, which is what the model runs at.
        XCTAssertEqual(Pickers.heldLocation(for: .stt, mix: mix, options: []), "eu")
        XCTAssertEqual(Pickers.heldLocation(for: .tts, mix: mix, options: mouth), "global")
        XCTAssertEqual(Pickers.heldLocation(for: .llm, mix: mix, options: []), "auto")
        XCTAssertNil(Pickers.heldLocation(for: .turn, mix: mix, options: []))
        XCTAssertNil(Pickers.heldLocation(for: .realtime, mix: mix, options: []))
    }

    /// ⛔ A MODEL REFUSED IN THE REGION IS NOT OFFERED, unless it is the one held.
    func testRealtimeModelsLeaveOutTheRefusedOneUnlessHeld() throws {
        let studio = try VoiceStudioFixture.response {
            try $0.editEntry(["catalog", "realtime"], where: ["model": VoiceStudioRules.gemini38Live]) {
                try $0.set("refusedInRegion", .bool(true))
            }
        }
        XCTAssertEqual(
            Pickers.realtimeModels(modelId: VoiceStudioRules.geminiLive25, in: studio).map(\.value),
            [VoiceStudioRules.geminiLive25]
        )
        let held = Pickers.realtimeModels(modelId: VoiceStudioRules.gemini38Live, in: studio)
        XCTAssertEqual(held.map(\.value), [VoiceStudioRules.gemini38Live, VoiceStudioRules.geminiLive25])
        XCTAssertEqual(held.first?.note, "Preview: processed globally by Google")
    }
}
