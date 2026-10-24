import DistrictModel
import Foundation
import XCTest

/// The notify-read token's DTO keeps its token out of every string, and the sender DTO
/// writes a missing name the way the server does.
final class NotifyReadResponsesTests: XCTestCase {
    private let response = NotifyTokenResponse(
        success: true,
        token: "secret-notify-jwt",
        expiresAt: "2026-11-23T00:00:00.000Z"
    )

    /// ⛔ THE TOKEN IS A BEARER SECRET: `description`, `debugDescription`, interpolation
    /// and `dump` all redact it.
    func testTheTokenIsRedactedEverywhereItCouldBePrinted() {
        var dumped = ""
        dump(response, to: &dumped)
        for text in [response.description, response.debugDescription, "\(response)", dumped] {
            XCTAssertFalse(text.contains("secret-notify-jwt"), text)
            XCTAssertTrue(text.contains("<redacted>"), text)
        }
        XCTAssertTrue(response.description.contains("2026-11-23T00:00:00.000Z"))
    }

    /// ⚠️ A NIL NAME IS AN EXPLICIT `null` ON THE WAY OUT, as the route sends it, rather
    /// than a dropped key.
    func testANilSenderNameEncodesAsAnExplicitNull() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let none = try String(bytes: encoder.encode(MessageSenderResponse(success: true, name: nil)), encoding: .utf8)
        let named = try String(bytes: encoder.encode(MessageSenderResponse(success: true, name: "A")), encoding: .utf8)

        XCTAssertEqual(none, #"{"name":null,"success":true}"#)
        XCTAssertEqual(named, #"{"name":"A","success":true}"#)
    }
}
