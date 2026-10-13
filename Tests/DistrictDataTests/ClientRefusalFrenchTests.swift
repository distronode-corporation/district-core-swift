@testable import DistrictData
import DistrictL10n
import DistrictModel
import XCTest

/// The core's own refusals, end to end: built under French, shown under French as the
/// catalog wrote them, never nil.
final class ClientRefusalFrenchTests: XCTestCase {
    func testAnAttachmentRefusalKeepsItsSentenceInFrench() {
        L10nRuntime.withLocale(.frCA) {
            let refusal = MediaUploadLimits.refusal(mimeType: "image/gif", byteCount: 0)
            XCTAssertNil(refusal?.code)
            XCTAssertEqual(refusal?.localizedMessage, InboxCopy.attachmentEmpty)
        }
    }

    /// And the same failure from the server, with no code, is the screen's to word.
    func testTheServersSentenceWithNoCodeIsLeftToTheScreen() {
        L10nRuntime.withLocale(.frCA) {
            let server = ApiError.http(status: 400, message: "Attachments are not allowed here.")
            XCTAssertNil(server.localizedMessage)
        }
    }
}
