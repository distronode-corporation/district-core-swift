import DistrictModel
import Foundation

// A fresh re-authentication and the account deletion it guards (vendored by #62), in a file of
// their own because `ImplementedFixtures.swift` is at its 500-line ceiling.

extension ImplementedFixtures {
    static var nativeReauth: [ImplementedFixture] {
        [
            gate("district-native-reauth.json", NativeReauthResponse.self),
            gate("district-account-delete.json", AccountDeleteResponse.self),
        ]
    }
}
