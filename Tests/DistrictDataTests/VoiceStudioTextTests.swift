@testable import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// The sentences a client builds from the service's templates: the unsaved meter's headline,
/// a bare median, and the "Based on" line, in English and in French.
final class VoiceStudioTextTests: XCTestCase {
    private typealias Text = VoiceStudioText

    /// The fixture with its templates in French, as `voiceStudioI18n.ts` writes them.
    private func french() throws -> VoiceStudioResponse {
        let nbsp = "\u{00A0}"
        let templates: [String: String] = [
            "meterAbout": "Environ {ms}\(nbsp)ms",
            "meterAtLeast": "Au moins {ms}\(nbsp)ms",
            "meterNone": "Pas encore mesuré",
            "meterPartial": "Certaines étapes ne sont pas encore mesurées, donc le délai réel est plus long.",
            "numberGrouping": nbsp,
            "basedOnOne": "Basé sur {recipe}, 1 modification.",
            "basedOnMany": "Basé sur {recipe}, {n} modifications.",
        ]
        return try VoiceStudioFixture.response { document in
            try document.edit(["labels"]) { labels in
                for (key, value) in templates {
                    try labels.set(key, .string(value))
                }
            }
        }
    }

    // MARK: - The templates as the service sends them

    func testTheEnglishTemplatesAreTheServices() throws {
        let labels = try VoiceStudioFixture.response().labels
        XCTAssertEqual(labels.meterAbout, "About {ms}\u{00A0}ms")
        XCTAssertEqual(labels.meterAtLeast, "At least {ms}\u{00A0}ms")
        XCTAssertEqual(labels.meterNone, "Not measured yet")
        XCTAssertEqual(labels.meterPartial, "Some steps are not measured yet, so the real time is longer.")
        XCTAssertEqual(labels.numberGrouping, ",")
        XCTAssertEqual(labels.basedOnOne, "Based on {recipe}, 1 change.")
        XCTAssertEqual(labels.basedOnMany, "Based on {recipe}, {n} changes.")
    }

    // MARK: - Grouping

    func testEnglishGroupsWithACommaFromTheRight() throws {
        let labels = try VoiceStudioFixture.response().labels
        XCTAssertEqual(Text.grouped(7, labels), "7")
        XCTAssertEqual(Text.grouped(970, labels), "970")
        XCTAssertEqual(Text.grouped(1234, labels), "1,234")
        XCTAssertEqual(Text.grouped(12345, labels), "12,345")
        XCTAssertEqual(Text.grouped(1_234_567, labels), "1,234,567")
    }

    func testFrenchGroupsWithANoBreakSpace() throws {
        let labels = try french().labels
        XCTAssertEqual(Text.grouped(7, labels), "7")
        XCTAssertEqual(Text.grouped(970, labels), "970")
        XCTAssertEqual(Text.grouped(1234, labels), "1\u{00A0}234")
        XCTAssertEqual(Text.grouped(12345, labels), "12\u{00A0}345")
        XCTAssertEqual(Text.grouped(1_234_567, labels), "1\u{00A0}234\u{00A0}567")
    }

    /// The total is a whole number of milliseconds; a fractional sum is rounded, never shown.
    func testAFractionalSumIsRounded() throws {
        let labels = try VoiceStudioFixture.response().labels
        XCTAssertEqual(Text.grouped(969.6, labels), "970")
    }

    // MARK: - The headline

    func testTheEnglishHeadlines() throws {
        let labels = try VoiceStudioFixture.response().labels
        XCTAssertEqual(Text.headline(.local(ms: 970, atLeast: false), labels: labels), "About 970\u{00A0}ms")
        XCTAssertEqual(Text.headline(.local(ms: 1234, atLeast: true), labels: labels), "At least 1,234\u{00A0}ms")
        XCTAssertEqual(Text.headline(.local(ms: 12345, atLeast: false), labels: labels), "About 12,345\u{00A0}ms")
        XCTAssertEqual(Text.headline(VoiceStudioMeterHeadline.none, labels: labels), "Not measured yet")
        XCTAssertEqual(Text.headline(.server("About 970 ms"), labels: labels), "About 970 ms")
    }

    func testTheFrenchHeadlines() throws {
        let labels = try french().labels
        XCTAssertEqual(Text.headline(.local(ms: 970, atLeast: false), labels: labels), "Environ 970\u{00A0}ms")
        XCTAssertEqual(
            Text.headline(.local(ms: 1234, atLeast: true), labels: labels),
            "Au moins 1\u{00A0}234\u{00A0}ms"
        )
        XCTAssertEqual(
            Text.headline(.local(ms: 12345, atLeast: false), labels: labels),
            "Environ 12\u{00A0}345\u{00A0}ms"
        )
        XCTAssertEqual(Text.headline(VoiceStudioMeterHeadline.none, labels: labels), "Pas encore mesuré")
    }

    /// ⛔ THE RULE REPRODUCES THE SERVICE: every meter sentence in the read, rebuilt from its
    /// own `ms` and `atLeast`, is the sentence the service wrote.
    func testTheTemplatesReproduceEveryMeterInTheRead() throws {
        let studio = try VoiceStudioFixture.response()
        let current = studio.latency
        XCTAssertEqual(rebuilt(current.ms, atLeast: current.atLeast, studio.labels), current.text)
        for meter in studio.recipes.map(\.timeToFirstWord) {
            XCTAssertEqual(rebuilt(meter.ms, atLeast: meter.atLeast, studio.labels), meter.text)
        }
    }

    private func rebuilt(_ ms: Double?, atLeast: Bool, _ labels: VoiceStudioLabels) -> String {
        guard let ms else { return Text.headline(VoiceStudioMeterHeadline.none, labels: labels) }
        return Text.headline(.local(ms: ms, atLeast: atLeast), labels: labels)
    }

    // MARK: - A bare median

    func testABareMedianIsGroupedWithTheTemplatesUnit() throws {
        let english = try VoiceStudioFixture.response().labels
        XCTAssertEqual(Text.latency(.milliseconds(1234), labels: english), "1,234\u{00A0}ms")
        let french = try french().labels
        XCTAssertEqual(Text.latency(.milliseconds(90), labels: french), "90\u{00A0}ms")
        XCTAssertEqual(Text.latency(.server("Lab: 150 ms"), labels: french), "Lab: 150 ms")
        XCTAssertEqual(Text.latency(VoiceStudioLatencyText.none, labels: french), french.notMeasured)
    }

    /// ⛔ THE UNIT IS THE TEMPLATE'S: what follows `{ms}` in `meterAbout`, never typed here.
    func testABareMediansUnitIsWhatFollowsThePlaceholder() throws {
        let edited = try VoiceStudioFixture.response { document in
            try document.edit(["labels", "meterAbout"]) { $0 = .string("About {ms} msec") }
        }
        XCTAssertEqual(Text.latency(.milliseconds(90), labels: edited.labels), "90 msec")
        let bare = try VoiceStudioFixture.response { document in
            try document.edit(["labels", "meterAbout"]) { $0 = .string("About") }
        }
        XCTAssertEqual(Text.latency(.milliseconds(90), labels: bare.labels), "90")
    }

    // MARK: - Based on

    func testBasedOnInEnglish() throws {
        let labels = try VoiceStudioFixture.response().labels
        XCTAssertEqual(Text.basedOn(recipe: "Fastest", changes: 1, labels: labels), "Based on Fastest, 1 change.")
        XCTAssertEqual(Text.basedOn(recipe: "Fastest", changes: 2, labels: labels), "Based on Fastest, 2 changes.")
        // The count is plain digits, never grouped.
        XCTAssertEqual(
            Text.basedOn(recipe: "Fastest", changes: 1234, labels: labels),
            "Based on Fastest, 1234 changes."
        )
    }

    func testBasedOnInFrench() throws {
        let labels = try french().labels
        XCTAssertEqual(Text.basedOn(recipe: "Rapide", changes: 1, labels: labels), "Basé sur Rapide, 1 modification.")
        XCTAssertEqual(Text.basedOn(recipe: "Rapide", changes: 3, labels: labels), "Basé sur Rapide, 3 modifications.")
    }

    func testNothingIsSaidWithNoChangeOrNoRecipe() throws {
        let labels = try VoiceStudioFixture.response().labels
        XCTAssertNil(Text.basedOn(recipe: "Fastest", changes: 0, labels: labels))
        XCTAssertNil(Text.basedOn(recipe: "", changes: 2, labels: labels))
    }

    /// ⚠️ A RECIPE NAME IS THE SERVICE'S AND IS FILLED AS LITERAL TEXT, after the count.
    func testARecipeNameHoldingAPlaceholderIsLeftAlone() throws {
        let labels = try VoiceStudioFixture.response().labels
        XCTAssertEqual(Text.basedOn(recipe: "{n} {ms}", changes: 2, labels: labels), "Based on {n} {ms}, 2 changes.")
    }

    /// A template without its placeholder is shown as it is, not broken.
    func testATemplateWithoutItsPlaceholderIsUnchanged() {
        XCTAssertEqual(Text.fill("Not measured yet", "{ms}", with: "970"), "Not measured yet")
        XCTAssertEqual(Text.fill("{ms} and {ms}", "{ms}", with: "1"), "1 and {ms}")
    }

    // MARK: - The session's line

    func testTheSessionSaysWhatItIsBasedOn() throws {
        let studio = try VoiceStudioFixture.response()
        let session = VoiceStudioSession(studio: studio)
        XCTAssertNil(session.basedOn)
        let moved = session.withHeld(
            VoiceStudioState(
                engine: .chained(VoiceStudioFixture.fluxChain).withVoice("aura-2-luna-en"),
                realtimeTemperature: 0.7,
                bilingual: false,
                voiceStyle: nil
            )
        )
        XCTAssertEqual(moved.basedOn, "Based on Fastest, 1 change.")
    }
}
