@testable import DistrictModel
@testable import DistrictNetwork
import Foundation

extension EndpointTable {
    /// A fresh re-authentication and the account deletion, read off the service's routes.
    static func nativeReauth() -> [EndpointExpectation] {
        [
            EndpointExpectation(
                .nativeReauthSso,
                DistrictEndpoints.nativeReauthSso(
                    action: .deleteAccount,
                    code: "c_1",
                    codeVerifier: "v_1",
                    redirectUri: "district://auth/reauth"
                ),
                .post,
                "\(host)/api/auth/native/reauth/sso",
                .json(
                    #"{"action":"delete-account","code":"c_1","codeVerifier":"v_1","#
                        + #""redirectUri":"district://auth/reauth"}"#
                )
            ),
            EndpointExpectation(
                .nativeReauthPassword,
                DistrictEndpoints.nativeReauthPassword(action: .twoFactorChange, password: "pw", code: "123456"),
                .post,
                "\(host)/api/auth/native/reauth/password",
                .json(#"{"action":"2fa-change","code":"123456","password":"pw"}"#)
            ),
            EndpointExpectation(
                .deleteAccount,
                DistrictEndpoints.deleteAccount(confirmation: "you@example.test"),
                .delete,
                "\(host)/api/auth/delete-account",
                .json(#"{"confirmation":"you@example.test"}"#)
            ),
        ]
    }
}
