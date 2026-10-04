import DistrictModel
import DistrictNetwork
import Foundation

/// The scheduling admin's NON-RPC route: the image upload. (The recording download
/// beside it was retired with meeting recording, 2026-10-03.)
///
/// ⛔ A SEPARATE TYPE FROM ``SchedulingAdminRepository``, AND THE REASON IS THE
/// CONTRACT RATHER THAN TIDINESS. That repository's whole job is the op catalog's
/// ENVELOPE, reached through one generic `perform`; the upload is not in
/// `admin-ops.ts` at all. An image cannot travel through a zod-validated params
/// object without a base64 inflation on both sides of a hop that already has a
/// 5 MiB ceiling, so it takes multipart. Folding it into `perform` would mean a
/// generic that sometimes does not decode `data`.
///
/// ⚠️ THE FAILURE VOCABULARY IS SHARED ON PURPOSE. The upload maps through
/// ``SchedulingAdminError``, because a person who could not replace a logo and a
/// person who could not rename an event type are owed the same five recoveries,
/// and `admin-fetch.ts` performs the same collapse for the browser.
public struct SchedulingAdminMediaRepository: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    /// Publish a logo, a banner or the caller's own avatar.
    ///
    /// ⛔ IT ANSWERS THE RPC'S ENVELOPE WITHOUT BEING AN RPC. A scheduler refusal
    /// arrives as **HTTP 200** carrying `{ok:false, failure, status}`, exactly as
    /// on the catalog route and for the same reason, the request reached
    /// Distronode, cleared auth, cleared the role bar and the far end is what
    /// refused. A caller that read the status alone would report a rejected image
    /// as a successful upload, so the flag is decoded before the payload here just
    /// as it is in ``SchedulingAdminRepository``.
    ///
    /// ⛔ THE TARGETS DO NOT SHARE A BUDGET OR A ROLE. `logo` and `banner` are the
    /// WORKSPACE's public branding and are `client`, spending the 120-per-hour
    /// workspace bucket; `avatar` is the caller's OWN picture and is `viewer`,
    /// spending the 30-per-member one. One viewer uploading pictures used to lock
    /// every administrator out of every write for an hour.
    ///
    /// ⚠️ 415 AND 400 BOTH LAND ON ``SchedulingAdminError/unknown``, WHICH IS A
    /// KNOWN GAP RATHER THAN AN OVERSIGHT. The five-code vocabulary has no "wrong
    /// file type" arm and inventing a sixth here would make this client disagree
    /// with the browser about one refusal. The mitigation is on the way IN, not on
    /// the way out: offer only ``SchedulingUploadFile/acceptedMimeTypes`` in the
    /// picker. ⛔ **SVG is not one of them**, it is the obvious thing to want for
    /// a logo and it is a script-bearing document.
    public func upload(
        workspaceId: String,
        target: SchedulingAdminUploadTarget,
        file: SchedulingUploadFile
    ) async throws -> SchedulingUploadResult {
        let descriptor = DistrictEndpoints.schedulingAdminUpload(
            workspaceId: workspaceId,
            target: target,
            fileName: file.fileName,
            mimeType: file.mimeType,
            bytes: file.bytes
        )
        switch await client.sendUnmapped(descriptor) {
        case let .failure(error):
            // ⚠️ ONLY REACHED WHEN NO RESPONSE EXISTS, an unbuildable path, a
            // missing credential, a dead socket.
            throw SchedulingAdminRepository.error(forUnanswered: error)
        case let .success(raw):
            return try Self.decodeUpload(raw)
        }
    }

    /// The envelope walk, in the order ``SchedulingAdminRepository`` walks it.
    ///
    /// ⚠️ A `static` RATHER THAN A METHOD because it needs nothing from the
    /// instance, and `private` because the catalog route's copy, which has the
    /// `unknown_op` reporter this one cannot have, is the one a caller should
    /// reach for.
    private static func decodeUpload(_ raw: RawResponse) throws -> SchedulingUploadResult {
        guard (200 ... 299).contains(raw.statusCode) else {
            let body = try? JSONDecoder().decode(SchedulingAdminErrorBody.self, from: raw.body)
            throw SchedulingAdminRepository.error(forStatus: raw.statusCode, code: body?.error ?? "")
        }
        guard let head = try? JSONDecoder().decode(SchedulingAdminEnvelopeHead.self, from: raw.body) else {
            // A 2xx that is neither shape is a contract we cannot read, and it is
            // NOT a retry.
            throw SchedulingAdminError.unknown
        }
        guard head.ok else {
            throw SchedulingAdminError.failure(.forFailure(head.failure ?? ""))
        }
        do {
            return try JSONDecoder()
                .decode(SchedulingAdminSuccess<SchedulingUploadResult>.self, from: raw.body)
                .data
        } catch {
            // ⛔ NO BODY PREVIEW. This text can reach a screen.
            throw SchedulingAdminError.decoding(
                "The scheduler's answer to an image upload did not match the shape this app expects "
                    + "(\(raw.body.count) bytes)."
            )
        }
    }
}

/// One image, ready to send.
///
/// ⛔ THE PART IS NAMED `file` ON THE WAY OUT AND IS RENAMED AT THE FAR END. Our
/// route reads `form.get("file")` and forwards it to the fork under `logo`,
/// `banner` or `avatar`; a part named after the TARGET is "Missing file field"
/// here, before the scheduler is ever asked.
public struct SchedulingUploadFile: Equatable, Sendable {
    /// ⚠️ Carried for the far end's benefit, but omitting it makes the part a
    /// plain field rather than a file, at which point `file instanceof File`
    /// fails and the route answers 400.
    public let fileName: String
    public let mimeType: String
    public let bytes: Data

    public init(fileName: String, mimeType: String, bytes: Data) {
        self.fileName = fileName
        self.mimeType = mimeType
        self.bytes = bytes
    }

    /// The four types the route accepts, which are the FORK's set read rather
    /// than guessed (`internal/handler/image_upload.go`).
    ///
    /// ⛔ NO `image/svg+xml`, AND THAT IS THE ENTRY WORTH KNOWING. An SVG logo is
    /// the obvious thing to want and an SVG is a script-bearing document. The
    /// route refuses it with a **415** rather than letting the fork do it, so the
    /// customer gets a clear answer instead of a sniffed-content rejection.
    ///
    /// ⚠️ A COURTESY FILTER, NOT THE BOUNDARY. The fork sniffs the first 512 bytes
    /// rather than trusting the declared type, so a real SVG renamed `.png` and
    /// declared `image/png` still fails there. Checking here buys a better message,
    /// never a guarantee.
    public static let acceptedMimeTypes: Set<String> = [
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/webp",
    ]

    /// The route's own ceiling, checked before the remote call so an oversized
    /// upload costs one request rather than a 5 MiB body pushed at someone else's
    /// service first.
    public static let maxBytes = 5 * 1024 * 1024
}
