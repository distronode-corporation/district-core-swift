@testable import DistrictData
import DistrictModel
import DistrictNetwork
import XCTest

final class TwoStepSettingsRepositoryTests: XCTestCase {
    private static func json(_ body: String, _ status: Int = 200) -> HTTPResponse {
        HTTPResponse(statusCode: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }

    private static let reauthRequired = json(
        #"{"error":"Confirm it is you again, then change two-step verification.","code":"reauth_required"}"#,
        403
    )

    func testEnrolConfirmAndDisableEachAnswerTheirOutcome() async {
        let transport = RepositoryTransport([
            Self
                .json(
                    #"{"secret":"S","otpauthUri":"otpauth://totp/x?secret=S","qrDataUrl":"data:image/png;base64,AA"}"#
                ),
            Self.json(#"{"enrolled":true,"backupCodes":["aaaa-bbbb","cccc-dddd"]}"#),
            Self.json(#"{"enrolled":false}"#),
        ])
        let repository = TwoStepSettingsRepository(client: .repositoryTest(transport))
        let enrolment = await repository.enroll()
        let confirmed = await repository.confirm(totp: "123456")
        let disabled = await repository.disable()
        XCTAssertEqual(enrolment.successOnly?.secret, "S")
        XCTAssertEqual(enrolment.successOnly?.qrDataUrl, "data:image/png;base64,AA")
        XCTAssertEqual(confirmed.successOnly?.backupCodes, ["aaaa-bbbb", "cccc-dddd"])
        XCTAssertNoThrow(try disabled.get())
        // ⛔ ENROLLING AND DISABLING SEND NO BODY, and disabling no password: the proof stands in.
        XCTAssertEqual(transport.bodies, [#"{"totp":"123456"}"#])
        XCTAssertEqual(transport.requestedURLs.map { $0.components(separatedBy: "/api/").last }, [
            "auth/mfa/enroll", "auth/mfa/confirm", "auth/mfa/disable",
        ])
    }

    /// ⛔ WITHOUT A FRESH `2fa-change` PROOF EVERY STEP IS A 403 `reauth_required`, kept whole so
    /// the caller can open the re-authentication sheet and try again.
    func testAMissingProofIsReauthRequiredOnEveryStep() async {
        let transport = RepositoryTransport([Self.reauthRequired, Self.reauthRequired, Self.reauthRequired])
        let repository = TwoStepSettingsRepository(client: .repositoryTest(transport))
        let enrolment = await repository.enroll()
        let confirmed = await repository.confirm(totp: "123456")
        let disabled = await repository.disable()
        for failure in [enrolment.failureOnly, confirmed.failureOnly, disabled.failureOnly] {
            XCTAssertEqual(failure?.code, "reauth_required")
            XCTAssertEqual(failure?.httpStatus, 403)
        }
    }

    /// ⚠️ THE SERVICE'S OTHER REFUSALS KEEP THEIR CODES TOO.
    func testOtherRefusalsKeepTheServiceCode() async {
        let transport = RepositoryTransport([
            Self.json(
                #"{"error":"Two-step verification can only be changed from a browser signed in to this account.","#
                    + #""code":"browser_session_required"}"#,
                403
            ),
            Self.json(#"{"error":"That code is not valid.","code":"mfa_code_invalid"}"#, 400),
            Self.json(#"{"error":"Already on.","code":"MFA_ALREADY_ENABLED"}"#, 409),
        ])
        let repository = TwoStepSettingsRepository(client: .repositoryTest(transport))
        let browserOnly = await repository.enroll()
        let wrongCode = await repository.confirm(totp: "000000")
        let alreadyOn = await repository.enroll()
        XCTAssertEqual(browserOnly.failureOnly?.code, "browser_session_required")
        XCTAssertEqual(wrongCode.failureOnly?.code, "mfa_code_invalid")
        XCTAssertEqual(alreadyOn.failureOnly?.code, "MFA_ALREADY_ENABLED")
    }

    /// ⛔ A 200 THAT DOES NOT SAY THE FACTOR CHANGED IS NOT TAKEN AS A CHANGE.
    func testAnAnswerThatContradictsTheStepIsRefused() async {
        let transport = RepositoryTransport([
            Self.json(#"{"enrolled":false,"backupCodes":[]}"#),
            Self.json(#"{"enrolled":true}"#),
        ])
        let repository = TwoStepSettingsRepository(client: .repositoryTest(transport))
        let confirmed = await repository.confirm(totp: "123456")
        let disabled = await repository.disable()
        XCTAssertEqual(confirmed.failureOnly, .decoding("MfaConfirmResponse did not affirm success=true"))
        XCTAssertEqual(disabled.failureOnly, .decoding("MfaDisableResponse did not affirm success=true"))
    }
}
