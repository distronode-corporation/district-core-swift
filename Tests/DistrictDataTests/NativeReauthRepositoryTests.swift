@testable import DistrictData
import DistrictModel
import DistrictNetwork
import XCTest

final class NativeReauthRepositoryTests: XCTestCase {
    private static func json(_ body: String, _ status: Int = 200) -> HTTPResponse {
        HTTPResponse(statusCode: status, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
    }

    func testTheSheetCodeAndThePasswordEachAnswerHowLongTheProofStands() async {
        let transport = RepositoryTransport([
            Self.json(#"{"success":true,"action":"delete-account","expiresInSeconds":300}"#),
            Self.json(#"{"success":true,"action":"2fa-change","expiresInSeconds":120}"#),
        ])
        let repository = NativeReauthRepository(client: .repositoryTest(transport))
        let sheet = await repository.reauthenticate(
            action: .deleteAccount, code: "c", codeVerifier: "v", redirectUri: "district://auth/reauth"
        )
        let password = await repository.reauthenticate(action: .twoFactorChange, password: "pw")
        XCTAssertEqual(sheet.successOnly, 300)
        XCTAssertEqual(password.successOnly, 120)
        XCTAssertEqual(transport.bodies, [
            #"{"action":"delete-account","code":"c","codeVerifier":"v","redirectUri":"district:\/\/auth\/reauth"}"#,
            #"{"action":"2fa-change","password":"pw"}"#,
        ])
    }

    /// ⛔ A PROOF FOR ANOTHER ACTION IS REFUSED, NOT TRUSTED.
    func testAProofForAnotherActionIsRefused() async {
        let transport = RepositoryTransport(json: #"{"success":true,"action":"2fa-change","expiresInSeconds":300}"#)
        let result = await NativeReauthRepository(client: .repositoryTest(transport))
            .reauthenticate(action: .deleteAccount, password: "pw", code: "123456")
        XCTAssertEqual(result.failureOnly, .decoding("NativeReauthResponse is for another action"))
    }

    /// ⚠️ THE SERVICE'S CODE IS KEPT, so the caller can ask for the authenticator code.
    func testARefusalKeepsTheServiceCode() async {
        let transport = RepositoryTransport([
            Self.json(#"{"error":"Enter the code from your authenticator app.","code":"MFA_REQUIRED"}"#, 401),
        ])
        let result = await NativeReauthRepository(client: .repositoryTest(transport))
            .reauthenticate(action: .deleteAccount, password: "pw")
        XCTAssertEqual(result.failureOnly?.code, "MFA_REQUIRED")
    }

    func testDeletingAnswersWhetherVendorErasureIsPending() async {
        let transport = RepositoryTransport([
            Self.json(#"{"success":true,"accountDeleted":true,"externalErasurePending":true,"message":"Deleted."}"#),
            Self.json(#"{"success":true,"accountDeleted":false,"externalErasurePending":false}"#),
            Self.json(#"{"error":"Type the account's email address to confirm.","code":"confirmation_mismatch"}"#, 400),
        ])
        let repository = NativeReauthRepository(client: .repositoryTest(transport))
        let deleted = await repository.deleteAccount(confirmation: "you@example.test")
        let notDeleted = await repository.deleteAccount(confirmation: "you@example.test")
        let mismatch = await repository.deleteAccount(confirmation: "me@example.test")
        XCTAssertEqual(deleted.successOnly, true)
        XCTAssertNil(notDeleted.successOnly, "accountDeleted false is not a deletion")
        XCTAssertEqual(mismatch.failureOnly?.code, "confirmation_mismatch")
        XCTAssertEqual(transport.bodies.first, #"{"confirmation":"you@example.test"}"#)
        XCTAssertEqual(NativeReauthAction.allCases.map(\.rawValue), ["delete-account", "2fa-change"])
    }
}
