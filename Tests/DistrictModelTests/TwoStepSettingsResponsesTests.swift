import DistrictModel
import XCTest

final class TwoStepSettingsResponsesTests: XCTestCase {
    private static let secret = "JBSWY3DPEHPK3PXP"

    private static func enrolment() -> MfaEnrollResponse {
        MfaEnrollResponse(
            secret: secret,
            otpauthUri: "otpauth://totp/Distronode%3Ayou%40example.test?secret=\(secret)&issuer=Distronode",
            qrDataUrl: "data:image/png;base64,iVBORw0KGgoQRPAYLOAD"
        )
    }

    private static func texts(_ value: some Any) -> [String] {
        var dumped = ""
        dump(value, to: &dumped)
        return [String(describing: value), String(reflecting: value), "\(value)", dumped]
    }

    /// ⛔ THE SECRET, THE URI THAT CARRIES IT AND THE QR CODE OF IT NEVER REACH A LOG, `dump`
    /// included.
    func testTheEnrolmentSecretIsRedacted() {
        let enrolment = Self.enrolment()
        for text in Self.texts(enrolment) + [enrolment.description, enrolment.debugDescription] {
            XCTAssertFalse(text.contains(Self.secret), text)
            XCTAssertFalse(text.contains("otpauth://"), text)
            XCTAssertFalse(text.contains("QRPAYLOAD"), text)
            XCTAssertFalse(text.contains("data:image"), text)
            XCTAssertTrue(text.contains("<redacted>"), text)
        }
    }

    /// ⛔ THE RECOVERY CODES NEVER REACH A LOG; only how many there are.
    func testTheRecoveryCodesAreRedacted() {
        let confirmed = MfaConfirmResponse(enrolled: true, backupCodes: ["aaaa-bbbb", "cccc-dddd"])
        for text in Self.texts(confirmed) + [confirmed.description, confirmed.debugDescription] {
            XCTAssertFalse(text.contains("aaaa-bbbb"), text)
            XCTAssertFalse(text.contains("cccc-dddd"), text)
            XCTAssertTrue(text.contains("<2 redacted>"), text)
            XCTAssertTrue(text.contains("true"), text)
        }
    }

    /// The redaction is only in what is printed: the values themselves are whole.
    func testTheValuesThemselvesAreWhole() {
        XCTAssertEqual(Self.enrolment().secret, Self.secret)
        XCTAssertTrue(Self.enrolment().otpauthUri.contains("secret=\(Self.secret)"))
        XCTAssertEqual(MfaConfirmResponse(enrolled: true, backupCodes: ["a"]).backupCodes, ["a"])
    }
}
