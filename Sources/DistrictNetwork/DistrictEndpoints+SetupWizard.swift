import DistrictModel
import Foundation

/// The setup wizard's writes and the reads its steps make beside ``districtSetup(workspaceId:)``.
///
/// ⛔ OWNER ONLY, AND THE OWNER IS THE WORKSPACE'S `ownerId`, NOT A ROLE: every `setup/*` route
/// answers a member or an admin with 403, and a workspace that predates the wizard with 409
/// `setup_not_available`. ``workspaceConnections(workspaceId:)`` is the exception, open to
/// every member.
public extension DistrictEndpoints {
    /// Saves step states and business facts, and answers the whole setup state after the
    /// write (the same body as the GET).
    ///
    /// ⛔ STEP STATES ONLY IN `setupProgress`. The service strips anything else (the paid
    /// stamp, the consent record, the forwarding check), so nothing here can send them.
    /// ⚠️ EACH `businessFacts` SECTION PRESENT REPLACES THAT SECTION WHOLE, a list is sent in
    /// full, and an explicit null clears it; an absent section is left alone.
    static func districtSetupPatch(
        workspaceId: String,
        steps: [SetupStep: SetupStepState] = [:],
        businessFacts: WireJSON? = nil
    ) -> ApiRequestDescriptor {
        let stepPairs = SetupStep.allCases.compactMap { step in
            steps[step].map { (step.rawValue, JSONValue.string($0.rawValue)) }
        }
        return ApiRequestDescriptor(
            .districtSetupPatch,
            .patch,
            DistrictPaths.districtSetup,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("setupProgress", stepPairs.isEmpty ? nil : .object([("steps", .object(stepPairs))])),
                ("businessFacts", businessFacts.map(JSONValue.carrying)),
            ]))
        )
    }

    /// Drafts the business's facts from its own website, in `locale` (`"fr"`, else English).
    /// Never writes.
    static func setupLookup(workspaceId: String, websiteUrl: String, locale: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .setupLookup,
            .post,
            DistrictPaths.setupLookup,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("locale", .string(locale == "fr" ? "fr" : "en")),
                ("websiteUrl", .string(websiteUrl)),
            ]))
        )
    }

    /// Has the receptionist call `phone`. ⛔ THE CONSENT IS RECORDED BY THE SERVICE, with its
    /// own wording for the owner's locale, at this call; there is nothing to send for it.
    static func setupTestCall(workspaceId: String, phone: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .setupTestCall,
            .post,
            DistrictPaths.setupTestCall,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("phone", .string(phone)),
            ]))
        )
    }

    /// The latest forwarding check and how many are left today.
    static func forwardingCheck(workspaceId: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .forwardingCheck,
            .get,
            DistrictPaths.setupForwardingCheck,
            query: [ApiQueryItem("workspaceId", workspaceId)]
        )
    }

    /// Places a check call to the business line (E.164) and answers 202 with the pending check.
    static func forwardingCheckStart(
        workspaceId: String,
        businessLine: String,
        mode: ForwardingCheckMode
    ) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .forwardingCheckStart,
            .post,
            DistrictPaths.setupForwardingCheck,
            body: .json(.object([
                ("workspaceId", .string(workspaceId)),
                ("businessLine", .string(businessLine)),
                ("mode", .string(mode.rawValue)),
            ]))
        )
    }

    /// The workspace's connection rows, and for a non-viewer which calendar is in use.
    static func workspaceConnections(workspaceId: String) -> ApiRequestDescriptor {
        ApiRequestDescriptor(
            .workspaceConnections,
            .get,
            DistrictPaths.workspaceConnections,
            query: [ApiQueryItem("workspaceId", workspaceId)]
        )
    }
}

extension DistrictPaths {
    /// Here rather than in `DistrictPaths.swift`, which is at its 500-line ceiling.
    static let setupLookup = districtSetup + ["lookup"]
    static let setupTestCall = districtSetup + ["test-call"]
    static let setupForwardingCheck = districtSetup + ["forwarding-check"]
    static let workspaceConnections = ["api", "district", "connections"]
}
