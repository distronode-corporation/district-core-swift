import Foundation

/// `GET /api/auth/mfa`: whether the account has a second factor, and how many recovery codes
/// are left.
///
/// ⚠️ COUNTS AND BOOLEANS ONLY, BY THE SERVICE'S DESIGN: the secret leaves it once, at enrolment,
/// and the recovery codes once, at confirmation, so nothing here needs redacting.
public struct MfaStatusResponse: Codable, Sendable, Equatable {
    public let enrolled: Bool
    /// When the factor was turned on, ISO-8601 UTC with milliseconds, or nil while it is off.
    ///
    /// ⚠️ A STRING, NOT A PARSED DATE, like `expiresAt` on ``NotifyTokenResponse``;
    /// ``WireInstant/parse(_:)`` reads it.
    public let enrolledAt: String?
    public let backupCodesRemaining: Int
    /// Whether the website would let this account turn the factor off: false for an account
    /// without a password, because a browser re-proves the password to disable.
    ///
    /// ⚠️ NOT A LIMIT ON AN APP. An app's `2fa-change` proof stands in for the password, so
    /// `TwoStepSettingsRepository.disable()` works for a passwordless account too.
    public let canDisable: Bool

    public init(enrolled: Bool, enrolledAt: String?, backupCodesRemaining: Int, canDisable: Bool) {
        self.enrolled = enrolled
        self.enrolledAt = enrolledAt
        self.backupCodesRemaining = backupCodesRemaining
        self.canDisable = canDisable
    }
}

/// `POST /api/auth/mfa/enroll`: a new, not yet confirmed authenticator secret.
///
/// ⛔ ALL THREE FIELDS ARE THE SECRET: `otpauthUri` carries it as a query item and `qrDataUrl`
/// is that URI as a picture. They are left out of ``description``, ``debugDescription`` and the
/// mirror, so logging this value never prints them. The service hands it over once and has no
/// read path that shows it again.
public struct MfaEnrollResponse: Codable, Sendable, Equatable {
    /// The base32 key, for typing into an authenticator by hand.
    public let secret: String
    /// The `otpauth://` URI an authenticator app opens.
    public let otpauthUri: String
    /// A `data:image/png;base64,...` QR code of ``otpauthUri``, rendered by the service.
    public let qrDataUrl: String

    public init(secret: String, otpauthUri: String, qrDataUrl: String) {
        self.secret = secret
        self.otpauthUri = otpauthUri
        self.qrDataUrl = qrDataUrl
    }
}

/// `POST /api/auth/mfa/confirm`: the factor is on, and these are its recovery codes.
///
/// ⛔ THE RECOVERY CODES ARE CREDENTIALS, shown once (the service stores only their hashes).
/// Only their count reaches ``description``, ``debugDescription`` and the mirror.
public struct MfaConfirmResponse: Codable, Sendable, Equatable {
    public let enrolled: Bool
    public let backupCodes: [String]

    public init(enrolled: Bool, backupCodes: [String]) {
        self.enrolled = enrolled
        self.backupCodes = backupCodes
    }
}

/// `POST /api/auth/mfa/disable`: the factor and its recovery codes are gone.
public struct MfaDisableResponse: Codable, Sendable, Equatable {
    public let enrolled: Bool
}

extension MfaEnrollResponse: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// ⛔ REDACTED FOR `dump` AND EVERY OTHER MIRROR-BASED PRINT TOO, as ``HQVoiceTokenResponse``.
    public var customMirror: Mirror {
        Mirror(self, children: [
            "secret": "<redacted>",
            "otpauthUri": "<redacted>",
            "qrDataUrl": "<redacted>",
        ])
    }

    public var description: String {
        "MfaEnrollResponse(secret: <redacted>, otpauthUri: <redacted>, qrDataUrl: <redacted>)"
    }

    public var debugDescription: String {
        description
    }
}

extension MfaConfirmResponse: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var customMirror: Mirror {
        Mirror(self, children: [
            "enrolled": enrolled,
            "backupCodes": "<\(backupCodes.count) redacted>",
        ])
    }

    public var description: String {
        "MfaConfirmResponse(enrolled: \(enrolled), backupCodes: <\(backupCodes.count) redacted>)"
    }

    public var debugDescription: String {
        description
    }
}
