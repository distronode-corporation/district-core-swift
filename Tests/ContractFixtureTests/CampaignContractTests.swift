import ContractGateSupport
import DistrictModel
import Foundation
import XCTest

/// The AI campaign launcher's answer, read the way a results screen reads it. The strict
/// gate (`ImplementedFixtures.campaigns`) proves the keys; this proves the values.
final class CampaignContractTests: XCTestCase {
    /// One row per outcome, and a `success` that is not a call going out: one of three
    /// contacts is queued.
    func testTheFixtureCarriesOneRowPerOutcome() throws {
        let launch = try StrictDecodeVerifier.verify(
            fixture: "district-calls-outbound.json", as: AICampaignLaunchResponse.self
        )
        XCTAssertTrue(launch.success)
        XCTAssertEqual(launch.queuedCount, 1)
        XCTAssertEqual(launch.results.map(\.status), [.queued, .skipped, .failed])
        let queued = launch.results[0]
        XCTAssertEqual(queued.callId, "CAabababababababababababababababab")
        XCTAssertEqual(queued.provider, "twilio")
        XCTAssertNil(queued.code)
        XCTAssertNotNil(launch.results[1].code)
        XCTAssertNil(launch.results[2].code, "a failed dial carries no code")
    }

    /// ⛔ THE CODE THE ROUTE REALLY SENDS FOR A DNC CONTACT, through the same gate. The
    /// vendored fixture still says `do_not_call` until the service regenerates it, so this
    /// body is what makes that correction a no-op for the type.
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
