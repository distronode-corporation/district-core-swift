import DistrictModel
import Foundation

/// A 2xx body this client does not have a DTO for yet.
///
/// ⛔ A DELIBERATE PLACEHOLDER WITH A BURN-DOWN, NOT A PERMANENT ESCAPE HATCH.
/// The contract gate wires every fixture in with a counted, printed skip-list so the
/// DTO burn-down is visible; ``UntypedEndpoints/all`` is the same idea one layer
/// up, listing every endpoint still answering as bytes. An endpoint leaves that
/// list the day its fixture is implemented and its DTO lands in `DistrictModel`.
///
/// ⚠️ THE PARSE IS LENIENT AND THAT IS THE SHIPPED BEHAVIOUR ON PURPOSE. Strict
/// in the gate, lenient in the field: a field added server-side reds CI through
/// the contract fixtures, and degrades to "ignored" on already-installed builds
/// rather than breaking every response on every phone.
public struct RawResponse: Sendable, Equatable {
    public let statusCode: Int
    /// The bytes exactly as they arrived.
    public let body: Data
    /// The parsed document, or nil when the body was empty or not JSON at all.
    ///
    /// ⚠️ NIL IS NOT AN ERROR HERE. A captive portal answers 200 with an HTML
    /// login page for every request the app makes; a caller that needs JSON
    /// should say so rather than assume.
    public let json: JSONValue?

    /// The `X-Distronode-Error-Code` header, the one header a failure body needs beside
    /// it. ``ApiErrorNormalizer/apiError(statusCode:body:headerCode:)`` reads it when the
    /// body names no code.
    ///
    /// ⚠️ ONE HEADER, NOT ALL OF THEM. This type is compared whole in tests, and the
    /// others are the transport's business.
    public let errorCodeHeader: String?

    init(statusCode: Int, body: Data, errorCodeHeader: String? = nil) {
        self.statusCode = statusCode
        self.body = body
        self.errorCodeHeader = errorCodeHeader
        json = JSONWire.decode(body)
    }
}

extension RawResponse {
    /// The response as ``ApiClient`` hands it on: the body, nil read as empty, and the
    /// error-code header.
    init(_ response: HTTPResponse) {
        self.init(
            statusCode: response.statusCode,
            body: response.body ?? Data(),
            errorCodeHeader: response.header(ApiErrorCode.header)
        )
    }
}
