import DistrictModel
import Foundation

// The decline and the notification extension's sender name, in a file of their own.
//
// ⛔ SPLIT OUT BECAUSE `ImplementedFixtures.swift` IS AT ITS 500-LINE CEILING, the reason
// every other `ImplementedFixtures+*.swift` sibling gives.

extension ImplementedFixtures {
    // MARK: - A person's decline, and a lock screen's sender name

    /// ⛔ THREE FILES ARRIVED WITH THEIR ROUTES (8.0.0), so
    /// ``ContractManifest/expectedFixtureCount`` moves by three here and none of them
    /// visits ``ContractManifest/unimplemented``: each landed with its DTO and the
    /// repository that decodes it.
    ///
    /// ⚠️ THE DECLINE LANDS ON THE SHARED ``SuccessResponse``, like the push
    /// registration and the device routes. Its 200 says nothing else, by design: the
    /// route is idempotent and fails open.
    ///
    /// ⚠️ THE SENDER FIXTURE NAMES A CONTACT, so it needs no allowlist entry. The
    /// route's other 200, `"name": null` for a thread with no named contact, is decoded
    /// from bytes in `InboxSenderNameTests` rather than given a fixture: the corpus is
    /// the server's, and a file added here fails the count on both clients.
    static var notifyAndDecline: [ImplementedFixture] {
        [
            gate("district-call-decline.json", SuccessResponse.self),
            // ⚠️ 8.1.0, the Live Activity token registration: one more file, the
            // same shared envelope.
            gate("district-call-live-activity.json", SuccessResponse.self),
            gate("district-message-sender.json", MessageSenderResponse.self),
            gate("district-notify-token.json", NotifyTokenResponse.self),
        ]
    }
}
