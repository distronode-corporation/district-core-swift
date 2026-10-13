import DistrictL10n
import DistrictModel
import DistrictNetwork
import Foundation

/// The signed-in person's own settings.
///
/// ⚠️ UNUSED BY THE 7.x APPS UNTIL THEIR 3.0, which writes the language on sign-in and
/// whenever the device language changes, so email and the other server text match the
/// app. Until then nothing calls it and the server keeps choosing from the website's
/// menu and the browser.
public struct AccountSettingsRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// Store `locale` as the language the server writes to this person in.
    public func saveLocale(_ locale: L10nLocale) async -> Result<Void, ApiError> {
        let outcome = await client.send(DistrictEndpoints.saveLocale(locale), as: SuccessResponse.self)
        return outcome
            .flatMap { ResponseEnvelope.affirm("AccountSettingsResponse", $0.success, $0) }
            .map { _ in }
    }
}
