import Foundation

/// The live telemetry protocol's constants and timing rules, as pure functions.
///
/// The protocol, as the server speaks it:
///
/// 1. `POST /api/district/telemetry/token` with the workspace mints a credential
///    that lives fifteen minutes and names the socket's address, which depends on
///    the workspace's region.
/// 2. The client opens that address with `?workspaceId=` added and offers two
///    subprotocols: ``subprotocol``, then the credential as
///    `distronode.token.<token>`. The server must select the first.
/// 3. The server checks the credential and the membership after the handshake and
///    closes the socket if either fails: ``closeUnauthorized`` (4401) for the
///    credential, ``closeForbidden`` (4403) for the membership or a server that
///    does not serve the workspace's region.
/// 4. While open, the server relays every event for the workspace as one text
///    message, pings every thirty seconds, re-checks the membership and the session
///    every sixty, and closes with 4401 once the credential has expired.
/// 5. The client may send three ops as text messages (`DistrictModel.TranscriptClientOp`):
///    subscribe to one call's live transcript, unsubscribe, and `socket.mode` to stop
///    the workspace-wide relay. The server keeps them per socket, so they are sent again
///    on every open (see ``TelemetryConnection``). A refused op is answered with a
///    `transcript_error` event; the socket stays open.
///
/// Ported from the Linux desktop client's `district-live` crate, behaviour for
/// behaviour, with one deliberate change noted on ``backoffMilliseconds(failures:jitter:)``.
public enum TelemetryProtocol {
    /// ⛔ OFFERED FIRST, AND THE SERVER MUST SELECT IT. A connection on which the
    /// server selected anything else, or nothing, is refused: it speaks another
    /// version, or it selected the CREDENTIAL, which also means it echoed the
    /// credential back in a response header.
    public static let subprotocol = "distronode.telemetry.v1"

    /// The prefix of the second subprotocol, which carries the credential.
    ///
    /// ⛔ THE TOKEN TRAVELS IN `Sec-WebSocket-Protocol`, NEVER IN THE URL, so it
    /// stays out of every access log between here and the broadcaster.
    public static let tokenSubprotocolPrefix = "distronode.token."

    /// The credential was refused (expired, revoked, or not checkable just then).
    /// Mint a new one and reconnect.
    public static let closeUnauthorized = 4401

    /// The member may not stream this workspace, or this server does not serve its
    /// region. ⛔ A new credential changes nothing, so the connection stops.
    public static let closeForbidden = 4403

    /// How long before expiry the socket is replaced: the server closes a socket
    /// once its credential expires, so it is replaced first.
    public static let renewalLeadMilliseconds: Int64 = 60000

    /// The shortest a socket runs before it is replaced, so a credential already
    /// near expiry (a slow mint, a clock ahead of the server's) does not spin.
    public static let renewalFloorMilliseconds: Int64 = 5000

    /// The longest a socket runs before it is replaced, whatever expiry the
    /// credential claims.
    public static let renewalCeilingMilliseconds: Int64 = 60 * 60 * 1000

    /// The shortest wait before a reconnect.
    public static let backoffFloorMilliseconds: Int64 = 1000

    /// The longest wait before a reconnect, jitter included.
    public static let backoffCapMilliseconds: Int64 = 60000

    /// How long a socket may stay silent before it is presumed dead: three missed
    /// server pings. What a socket looks like after the network vanished without a
    /// word, or after the Mac slept.
    public static let silenceLimitMilliseconds: Int64 = 90000

    /// How long a socket must have stayed open to count as established. The server
    /// checks the credential and membership just after the handshake and closes at
    /// once if either fails, so a socket that closes sooner is a failed attempt and
    /// the next one backs off.
    public static let stableAfterMilliseconds: Int64 = 30000

    /// How long opening a socket (TCP, TLS and the handshake) may take.
    public static let connectTimeoutMilliseconds: Int64 = 15000

    /// The wait before reconnect attempt `failures` (1 for the first retry), for a
    /// `jitter` between 0 and 1.
    ///
    /// Exponential with "equal jitter": the ceiling doubles with each consecutive
    /// failure from 2 s up to ``backoffCapMilliseconds``, and the wait lies between
    /// half the ceiling and all of it, so the clients one server restart drops do
    /// not all come back in the same second.
    ///
    /// ⚠️ THE ONE DEPARTURE FROM THE LINUX CLIENT: its ceiling starts at 1 s, so its
    /// first retry can come after half a second. This one starts at 2 s, so no
    /// wait is ever under ``backoffFloorMilliseconds`` and every wait is still
    /// jittered. A non-finite jitter is read as the middle of the range.
    public static func backoffMilliseconds(failures: Int, jitter: Double) -> Int64 {
        let doublings = min(max(failures, 1) - 1, 16)
        let ceiling = min((2 * backoffFloorMilliseconds) << Int64(doublings), backoffCapMilliseconds)
        let spread = jitter.isFinite ? min(max(jitter, 0), 1) : 0.5
        return ceiling / 2 + Int64((Double(ceiling) * spread / 2).rounded(.down))
    }

    /// How long a socket opened at `now` on a credential expiring at `expiresAt`
    /// (both epoch milliseconds) runs before it is replaced.
    public static func renewalDelayMilliseconds(expiresAt: Int64, now: Int64) -> Int64 {
        let left = expiresAt &- now
        return min(max(left &- renewalLeadMilliseconds, renewalFloorMilliseconds), renewalCeilingMilliseconds)
    }

    /// Whether `token` can be carried in a subprotocol name: not empty, and only the
    /// characters of a compact JWT (base64url and dots).
    ///
    /// ⛔ ANYTHING ELSE WOULD BREAK THE HEADER'S COMMA-SEPARATED LIST, or be refused by
    /// the server after a handshake that cost a round trip, so it is refused here.
    public static func isPresentable(_ token: String) -> Bool {
        !token.isEmpty && token.unicodeScalars.allSatisfy(isTokenScalar)
    }

    private static func isTokenScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "-_.".unicodeScalars.contains(scalar))
    }

    /// The subprotocols to offer, in order: the version first, the credential second.
    ///
    /// ⛔ THE VERSION COMES FIRST because a server that simply selects the first offer
    /// would otherwise echo the credential back in its response headers.
    public static func offeredSubprotocols(token: String) -> [String] {
        [subprotocol, tokenSubprotocolPrefix + token]
    }

    /// The URL to dial for `workspaceId`: the server's `wsUrl` with the workspace
    /// added to the query and any fragment dropped.
    ///
    /// ⛔ PLAIN `ws` ONLY TO THIS MACHINE, so the credential never crosses a network
    /// unencrypted. Anything other than `wss` or `ws` is refused.
    public static func socketURL(wsUrl: String?, workspaceId: String) -> Result<URL, TelemetryEndpointError> {
        guard let wsUrl else { return .failure(.missing) }
        guard var components = URLComponents(string: wsUrl), let host = components.host, !host.isEmpty else {
            return .failure(.invalid)
        }
        switch components.scheme?.lowercased() {
        case "wss":
            break
        case "ws":
            guard isLoopback(host) else { return .failure(.insecure) }
        default:
            return .failure(.invalid)
        }
        components.fragment = nil
        // ⛔ ENCODED BY HAND, NOT THROUGH `queryItems`, WHICH LEAVES `&` AND `=` IN A
        // VALUE AS THEY ARE. A workspace id carrying either would add a parameter of
        // its own choosing to the URL the credential is presented at.
        let added = "workspaceId=" + percentEncoded(workspaceId)
        components.percentEncodedQuery = [components.percentEncodedQuery, added]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
            .joined(separator: "&")
        // ⚠️ `URLComponents.url` IS NEVER NIL FOR COMPONENTS THAT PARSED FROM A STRING,
        // kept their host and gained only an unreserved-or-escaped query, so the guards
        // above are the only refusals; the force states that rather than adding a branch
        // no input can reach.
        return .success(components.url!)
    }

    /// Every byte outside RFC 3986's unreserved set, as `%XX`.
    private static func percentEncoded(_ value: String) -> String {
        value.utf8.map { byte in
            let scalar = Unicode.Scalar(byte)
            let unreserved = scalar.isASCII
                && (CharacterSet.alphanumerics.contains(scalar) || "-._~".unicodeScalars.contains(scalar))
            return unreserved ? String(Character(scalar)) : String(format: "%%%02X", byte)
        }.joined()
    }

    /// ⚠️ IPv6 hosts arrive bracketed on one Foundation and bare on the other, so
    /// both spellings are accepted.
    private static func isLoopback(_ host: String) -> Bool {
        let bare = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if bare == "localhost" || bare == "::1" {
            return true
        }
        let octets = bare.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets[0] == "127" && octets.allSatisfy { UInt8($0) != nil }
    }
}

/// What is wrong with the socket address the server gave.
public enum TelemetryEndpointError: Error, Sendable, Equatable {
    /// The server gave none (`wsUrl: null`). Only a development server does that.
    case missing
    /// It is not a `wss` or `ws` URL with a host.
    case invalid
    /// It is `ws`, unencrypted, to a host other than this machine.
    case insecure
}
