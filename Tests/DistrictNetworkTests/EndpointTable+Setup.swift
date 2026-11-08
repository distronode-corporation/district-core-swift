@testable import DistrictModel
@testable import DistrictNetwork
import Foundation

extension EndpointTable {
    static func setup() -> [EndpointExpectation] {
        [
            EndpointExpectation(
                .districtSetup,
                DistrictEndpoints.districtSetup(workspaceId: "ws_1"),
                .get,
                "\(host)/api/district/setup?workspaceId=ws_1"
            ),
            // ⛔ STEP STATES ONLY inside `setupProgress`, and a section of facts sent whole.
            EndpointExpectation(
                .districtSetupPatch,
                DistrictEndpoints.districtSetupPatch(
                    workspaceId: "ws_1",
                    steps: [.business: .done, .number: .skipped],
                    businessFacts: .object(["timezone": .string("America/Toronto")])
                ),
                .patch,
                "\(host)/api/district/setup",
                .json(
                    #"{"businessFacts":{"timezone":"America/Toronto"},"#
                        + #""setupProgress":{"steps":{"business":"done","number":"skipped"}},"workspaceId":"ws_1"}"#
                )
            ),
            EndpointExpectation(
                .setupLookup,
                DistrictEndpoints.setupLookup(workspaceId: "ws_1", websiteUrl: "example.com", locale: "fr"),
                .post,
                "\(host)/api/district/setup/lookup",
                .json(#"{"locale":"fr","websiteUrl":"example.com","workspaceId":"ws_1"}"#)
            ),
            EndpointExpectation(
                .setupTestCall,
                DistrictEndpoints.setupTestCall(workspaceId: "ws_1", phone: "+14165550123"),
                .post,
                "\(host)/api/district/setup/test-call",
                .json(#"{"phone":"+14165550123","workspaceId":"ws_1"}"#)
            ),
            EndpointExpectation(
                .forwardingCheck,
                DistrictEndpoints.forwardingCheck(workspaceId: "ws_1"),
                .get,
                "\(host)/api/district/setup/forwarding-check?workspaceId=ws_1"
            ),
            EndpointExpectation(
                .forwardingCheckStart,
                DistrictEndpoints.forwardingCheckStart(
                    workspaceId: "ws_1",
                    businessLine: "+14165550123",
                    mode: .unanswered
                ),
                .post,
                "\(host)/api/district/setup/forwarding-check",
                .json(#"{"businessLine":"+14165550123","mode":"unanswered","workspaceId":"ws_1"}"#)
            ),
            EndpointExpectation(
                .workspaceConnections,
                DistrictEndpoints.workspaceConnections(workspaceId: "ws_1"),
                .get,
                "\(host)/api/district/connections?workspaceId=ws_1"
            ),
        ]
    }
}
