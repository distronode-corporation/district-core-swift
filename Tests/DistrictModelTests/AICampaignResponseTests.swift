import DistrictL10n
import DistrictModel
import Foundation
import XCTest

/// The AI campaign launcher's answer: an open status vocabulary, the queued count, and the
/// sentence beside each contact in each language.
final class AICampaignResponseTests: XCTestCase {
    /// ⚠️ A STATUS THIS BUILD DOES NOT KNOW IS KEPT, NOT A DECODE FAILURE: the calls are
    /// already placed by the time the body arrives. It round-trips as it was sent and is
    /// never counted as queued.
    func testAnUnknownStatusIsKeptAndNotCountedAsQueued() throws {
        let body = #"{"success":true,"results":[{"contactId":"c_1","status":"queued"},"#
            + #"{"contactId":"c_2","status":"deferred"}]}"#
        let launch = try JSONDecoder().decode(AICampaignLaunchResponse.self, from: Data(body.utf8))
        XCTAssertEqual(launch.results.map(\.status), [.queued, .unknown("deferred")])
        XCTAssertEqual(launch.queuedCount, 1)
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(launch.results[1].status), encoding: .utf8))
        XCTAssertEqual(encoded, #""deferred""#)
        XCTAssertEqual(["queued", "skipped", "failed"].map { AICampaignContactStatus(wire: $0).wire }, [
            "queued", "skipped", "failed",
        ])
    }

    /// ⛔ A KNOWN CODE READS THE CATALOG IN BOTH LANGUAGES, the service's catalog and this
    /// client's own (the two carrier codes) alike.
    func testAKnownCodeReadsTheCatalogInBothLanguages() {
        let dnc = AICampaignContactResult(
            contactId: "c_1", status: .skipped, error: "Opted out", code: "auto_dial_contact_opted_out"
        )
        let carrier = AICampaignContactResult(
            contactId: "c_2", status: .skipped, error: "x", code: "sinch_contact_required"
        )
        let disclosure = AICampaignContactResult(
            contactId: "c_3", status: .skipped, error: "x", code: "sinch_disclosure_unsupported"
        )
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(
                dnc.localizedMessage,
                "This contact has opted out of calls from this workspace (DNC)."
            )
            XCTAssertEqual(
                carrier.localizedMessage,
                "This workspace's carrier can only place this call to a saved contact."
            )
        }
        L10nRuntime.withLocale(.frCA) {
            XCTAssertEqual(
                dnc.localizedMessage,
                "Ce contact a choisi de ne plus recevoir d'appels de cet espace de travail (liste d'exclusion)."
            )
            XCTAssertEqual(
                carrier.localizedMessage,
                "Le transporteur de cet espace de travail ne peut appeler qu'un contact enregistré."
            )
            XCTAssertEqual(
                disclosure.localizedMessage,
                "Le transporteur de cet espace de travail ne peut pas transmettre l'avis d'appel par IA exigé."
            )
        }
    }

    /// Every code the brief for the launcher names has a sentence, so no skip or refusal the
    /// route can answer falls through to the screen's generic text.
    func testEveryLauncherCodeHasASentence() {
        let codes = [
            "auto_dial_contact_opted_out", "auto_dial_outside_hours", "auto_dial_country_not_permitted",
            "overage_cap_reached", "overage_spend_cap_reached", "workspace_dormant", "rate_limited",
            "sinch_contact_required", "sinch_disclosure_unsupported",
        ]
        for locale in [L10nLocale.en, .frCA] {
            L10nRuntime.withLocale(locale) {
                for code in codes {
                    XCTAssertNotNil(AICampaignSkipText.sentence(for: code), "\(code) has no sentence")
                }
            }
        }
    }

    /// Without a known code, English shows the server's detail and French shows nothing,
    /// never the English wire text.
    func testNoKnownCodeIsTheServersEnglishOrNothing() {
        let failed = AICampaignContactResult(contactId: "c_1", status: .failed, error: "Something went wrong.")
        let newer = AICampaignContactResult(
            contactId: "c_2",
            status: .skipped,
            error: "Later rule.",
            code: "a_newer_code"
        )
        let queued = AICampaignContactResult(contactId: "c_3", status: .queued, callId: "CA1")
        L10nRuntime.withLocale(.en) {
            XCTAssertEqual(failed.localizedMessage, "Something went wrong.")
            XCTAssertEqual(newer.localizedMessage, "Later rule.")
            XCTAssertNil(queued.localizedMessage)
        }
        L10nRuntime.withLocale(.frCA) {
            XCTAssertNil(failed.localizedMessage)
            XCTAssertNil(newer.localizedMessage)
        }
    }
}
