@testable import DistrictData
import DistrictModel
import DistrictNetwork
import Foundation
import XCTest

/// The Studio's read, and its save through the persona PATCH followed by the read.
final class VoiceStudioRepositoryTests: XCTestCase {
    private func repository(_ transport: RepositoryTransport) -> VoiceStudioRepository {
        VoiceStudioRepository(client: .repositoryTest(transport))
    }

    private func response(_ status: Int, _ body: String) -> HTTPResponse {
        HTTPResponse(statusCode: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }

    private let voiceOnly = VoiceStudioFields(modelId: "deepgram-pipeline", voice: "aura-2-luna-en")

    // MARK: - The read

    func testTheReadDecodesTheStudioForTheWorkspace() async throws {
        let transport = try RepositoryTransport(json: VoiceStudioFixture.body())
        let studio = try await repository(transport).load(workspaceId: "ws_1").get()
        XCTAssertEqual(studio.region, "us")
        XCTAssertEqual(
            transport.requestedURLs,
            ["https://www.distronode.com/api/district/workspace/persona/voice-studio?workspaceId=ws_1"]
        )
    }

    func testAReadThatDoesNotAffirmSuccessIsAFailure() async throws {
        let body = try VoiceStudioFixture.body()
            .replacingOccurrences(of: #""success": true"#, with: #""success": false"#)
        let result = await repository(RepositoryTransport(json: body)).load(workspaceId: "ws_1")
        XCTAssertEqual(result.failureOnly, .decoding("VoiceStudioResponse did not affirm success=true"))
    }

    // MARK: - The save

    /// ⛔ ONLY THE NAMED KEYS GO, AND THE STUDIO IS READ BACK AFTER THE 200.
    func testASaveSendsTheNamedKeysThenReadsTheStudioBack() async throws {
        let transport = try RepositoryTransport([
            response(200, #"{"success":true}"#),
            response(200, VoiceStudioFixture.body()),
        ])
        let outcome = await repository(transport).save(workspaceId: "ws_1", fields: voiceOnly, keys: [.voice])
        guard case let .saved(studio) = outcome else { return XCTFail("expected a saved outcome, got \(outcome)") }
        XCTAssertEqual(studio.region, "us")
        XCTAssertEqual(transport.bodies, [#"{"voice":"aura-2-luna-en","workspaceId":"ws_1"}"#])
        XCTAssertEqual(transport.requests.first?.method, .patch)
        XCTAssertEqual(transport.requests.count, 2)
    }

    /// ⛔ THE WRITE LANDED AND ONLY THE READ BACK FAILED: that is not "not saved".
    func testAFailedReReadIsSavedButStale() async {
        let transport = RepositoryTransport([response(200, #"{"success":true}"#), response(503, #"{"error":"Down"}"#)])
        let outcome = await repository(transport).save(workspaceId: "ws_1", fields: voiceOnly, keys: [.voice])
        XCTAssertEqual(outcome, .savedButStale(.http(status: 503, message: "Down")))
    }

    /// ⛔ A REFUSED CHAIN WROTE NOTHING, and the screen must be able to say which refusal.
    func testTheTwoStudioRefusalsAreNamed() async {
        let mix = #"{"success":false,"error":"That voice chain cannot be saved.","code":"invalid_engine_mix"}"#
        let refused = await repository(RepositoryTransport([response(400, mix)]))
            .save(workspaceId: "ws_1", fields: voiceOnly, keys: [.voice])
        XCTAssertEqual(refused, .notSaved(.invalidEngineMix("That voice chain cannot be saved.")))

        let region = #"{"success":false,"error":"Not here.","code":"model_unavailable_in_region"}"#
        let elsewhere = await repository(RepositoryTransport([response(400, region)]))
            .save(workspaceId: "ws_1", fields: voiceOnly, keys: [.voice])
        XCTAssertEqual(elsewhere, .notSaved(.modelUnavailableInRegion("Not here.")))
    }

    func testAnyOtherRefusalIsTheOrdinaryError() async {
        let limited = #"{"error":"Too many persona updates for this workspace. Please try again shortly."}"#
        let outcome = await repository(RepositoryTransport([response(429, limited)]))
            .save(workspaceId: "ws_1", fields: voiceOnly, keys: [.voice])
        XCTAssertEqual(
            outcome,
            .notSaved(.failed(.http(
                status: 429,
                message: "Too many persona updates for this workspace. Please try again shortly."
            )))
        )
        let html = await repository(RepositoryTransport([response(502, "<html>")]))
            .save(workspaceId: "ws_1", fields: voiceOnly, keys: [.voice])
        XCTAssertEqual(html, .notSaved(.failed(.http(status: 502, message: nil))))
    }

    /// ⛔ A 200 THAT DOES NOT AFFIRM SUCCESS WROTE NOTHING WE CAN VOUCH FOR.
    func testAWriteThatDoesNotAffirmSuccessIsNotSaved() async {
        let outcome = await repository(RepositoryTransport([response(200, #"{"success":false}"#)]))
            .save(workspaceId: "ws_1", fields: voiceOnly, keys: [.voice])
        XCTAssertEqual(outcome, .notSaved(.failed(.decoding("PersonaPatchResponse did not affirm success=true"))))
    }

    func testAnUnansweredWriteIsTheTransportError() {
        let refusal = VoiceStudioRepository.refusal(of: .failure(.transport("offline")))
        XCTAssertEqual(refusal, .failed(.transport("offline")))
    }
}
