import DistrictAuthCore
import XCTest

/// ``NativeMfaCode``: what the second-factor step sends, checked for shape against the
/// server's own routing rule (six ASCII digits is an authenticator code, anything else a
/// recovery code).
final class NativeMfaCodeTests: XCTestCase {
    func testAnAuthenticatorCodeIsSixAsciiDigitsWithSpacesIgnored() {
        XCTAssertEqual(NativeMfaCode.normalized("123456", as: .authenticator), "123456")
        XCTAssertEqual(NativeMfaCode.normalized(" 123 456\n", as: .authenticator), "123456")
        XCTAssertEqual(NativeMfaCode.authenticatorLength, 6)
    }

    /// ⛔ ANYTHING ELSE IS NOT SENT. Each would be a counted failure on the account's
    /// lockout, and a non-ASCII digit would be routed to the recovery codes.
    func testAnythingElseIsNotAnAuthenticatorCode() {
        for input in ["", "12345", "1234567", "12345a", "123-456", "\u{0661}23456", "\u{FF11}23456"] {
            XCTAssertNil(NativeMfaCode.normalized(input, as: .authenticator), input)
        }
    }

    /// The server normalises case and separators itself; this sends upper case with the
    /// hyphen kept, as the code is printed.
    func testARecoveryCodeIsSentUpperCasedWithSpacesRemoved() {
        XCTAssertEqual(NativeMfaCode.normalized("abcde-fghjk", as: .recovery), "ABCDE-FGHJK")
        XCTAssertEqual(NativeMfaCode.normalized(" ABCDE FGHJK ", as: .recovery), "ABCDEFGHJK")
        XCTAssertEqual(NativeMfaCode.normalized("abcd2345", as: .recovery), "ABCD2345")
    }

    /// ⛔ A SIX-DIGIT VALUE IS NEVER SENT AS A RECOVERY CODE: the server would check it
    /// against the authenticator instead. Too short or longer than the schema's 64 is
    /// refused too.
    func testARecoveryCodeRefusesTheAuthenticatorShapeAndBadLengths() {
        XCTAssertNil(NativeMfaCode.normalized("123456", as: .recovery))
        XCTAssertNil(NativeMfaCode.normalized("ABCD-EFG", as: .recovery), "seven characters once the hyphen goes")
        XCTAssertNil(NativeMfaCode.normalized("", as: .recovery))
        XCTAssertNil(NativeMfaCode.normalized(String(repeating: "A", count: 65), as: .recovery))
        XCTAssertNotNil(NativeMfaCode.normalized(String(repeating: "A", count: 64), as: .recovery))
    }

    func testTheAuthenticatorFieldKeepsAtMostSixAsciiDigits() {
        XCTAssertEqual(NativeMfaCode.authenticatorInput("12a3 45"), "12345")
        XCTAssertEqual(NativeMfaCode.authenticatorInput("Code: 123 456 789"), "123456")
        XCTAssertEqual(NativeMfaCode.authenticatorInput("\u{0661}\u{0662}"), "")
    }
}
