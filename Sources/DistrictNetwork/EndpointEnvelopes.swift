import Foundation

// How a route ANSWERS, as opposed to whether this client has ported a DTO for it.
//
// ⚠️ `RedirectEndpoints` USED TO BE THE FIRST LIST HERE AND IS GONE. Its two members,
// `calls/{id}/recording` and `scheduling/admin/download/{id}`, were retired by the
// server with recording itself (2026-10-03), and with them `ApiClient.redirectTarget`
// lost its only callers. A future route that answers a redirect to an object brings
// the list and the method back together, with a test.
//
// ⛔ SPLIT OUT OF `EndpointClassification.swift` BECAUSE THAT FILE REACHED
// SWIFTLINT'S 500-LINE CEILING AT 498 AND A NEW ENDPOINT FAMILY COULD NOT LAND,
// the support surface needed five lines and had two. The cut is on a real seam
// rather than at an arbitrary line: `UntypedEndpoints` and `TypedEndpoints` are the
// two halves of one burn-down and have to be read together, while the two enums
// here (now one) answer a different question entirely (what SHAPE comes back), are referenced
// by different code, and move for different reasons.
//
// ⚠️ THE TYPES, THEIR DOC COMMENTS AND THEIR MEMBERS ARE UNCHANGED BY THE MOVE.
// `EndpointSurfaceTests` asserts both sets by value, so a move that quietly dropped
// a member would fail there rather than in review.
//
// ⚠️ AND THE SEAM IS NOT PERFECT: `meetings` is on `BareArrayEndpoints` AND on
// `TypedEndpoints.all` in the other file, because the two lists answer different
// questions about the same route. Membership of one says nothing about the other.

/// The endpoints that answer a **bare JSON array** instead of the
/// `{success, …}` envelope almost every district route uses.
///
/// ⛔ DO NOT ADD A SYNTHETIC WRAPPER FOR THESE. `NextResponse.json(rows)` is what
/// the routes do; there is no `success` flag to check, and an empty array is a
/// legitimate answer that no envelope guard could distinguish from a broken read
/// anyway. A DTO that expected an object fails to decode every response these
/// routes send.
///
/// ⚠️ TWO OF THEM, AND THEY ARE EASY TO MISS BECAUSE THEIR SIBLINGS ARE
/// ENVELOPED: `calls` (while `calls/{id}` is enveloped) and `meetings` (while
/// `meetings/{id}` is a bare OBJECT, itself unlike both).
///
/// ⚠️ THE SUPPORT FAMILY IS NOT HERE AND MUST NOT BE ADDED. All five of its routes
/// carry the ordinary `{success, …}` envelope, including the list, which is what
/// makes `ResponseEnvelope.affirm` reachable on the one read where "we could not
/// look" rendered as "you have no support requests" is the expensive mistake.
public enum BareArrayEndpoints {
    public static let all: Set<EndpointID> = [.calls, .meetings]
}
