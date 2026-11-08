import ContractGateSupport
import DistrictModel
import Foundation
import XCTest

/// The AI campaign launcher's answer, read the way a results screen reads it. The strict
/// gate (`ImplementedFixtures.campaigns`) proves the keys; this proves the values.
final class CampaignContractTests: XCTestCase {
    /// One row per status and one skip per recipient rule, and a `success` that is not a
    /// call going out: one of five contacts is queued.
    func testTheFixtureCarriesOneRowPerOutcomeAndRule() throws {
        let launch = try StrictDecodeVerifier.verify(
            fixture: "district-calls-outbound.json", as: AICampaignLaunchResponse.self
        )
        XCTAssertTrue(launch.success)
        XCTAssertEqual(launch.queuedCount, 1)
        XCTAssertEqual(launch.results.map(\.status), [.queued, .skipped, .skipped, .skipped, .failed])
        let queued = launch.results[0]
        XCTAssertEqual(queued.callId, "CAabababababababababababababababab")
        XCTAssertEqual(queued.provider, "twilio")
        XCTAssertEqual(launch.results.map(\.code), [
            nil,
            "auto_dial_country_not_permitted",
            "auto_dial_outside_hours",
            "auto_dial_contact_opted_out",
            nil,
        ])
    }

    /// The settings save answers a bare `{success}`; the saved values are read back from
    /// `campaign-status`.
    func testTheSettingsSaveAnswersOnlySuccess() throws {
        let answer = try StrictDecodeVerifier.verify(
            fixture: "district-campaign-settings.json", as: SuccessResponse.self
        )
        XCTAssertTrue(answer.success)
    }

    /// ⛔ THE DNC CODE THE ROUTE SENDS, FROM AN INLINE BODY THROUGH THE SAME GATE, so the
    /// type is pinned to it independently of how the vendored fixture is regenerated.
    func testTheRoutesRealDncCodeDecodes() throws {
        let body = #"{"success":true,"results":[{"contactId":"contact_dnc","status":"skipped","#
            + #""error":"Number is on the Do Not Call list","code":"auto_dial_contact_opted_out"}]}"#
        let launch = try StrictDecodeVerifier.verify(
            name: "inline-calls-outbound-dnc", json: Data(body.utf8), as: AICampaignLaunchResponse.self
        )
        XCTAssertEqual(launch.results.map(\.code), ["auto_dial_contact_opted_out"])
        XCTAssertEqual(launch.results.map(\.status), [.skipped])
        XCTAssertEqual(launch.queuedCount, 0)
    }
}
