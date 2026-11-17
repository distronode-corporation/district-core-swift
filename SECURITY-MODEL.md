# Security model

This is the assurance case for District Core for Swift: who can attack it, where the trust
boundaries are, the secure design principles the code applies, and the common weaknesses
it counters, each with the mechanism and the test that holds it. The design is in
[ARCHITECTURE.md](ARCHITECTURE.md); how to report a problem, and what is in scope, is in
[SECURITY.md](SECURITY.md).

## What you can and cannot expect

The package is the part of the District AI apps that runs on Foundation alone. You can
expect it to sign in with PKCE, to refresh tokens without ever presenting one twice, to
keep the access token in memory only, to build every request from typed parts, to send
nothing a member did not ask for, and to refuse a hand-off address that is not the
service's own over HTTPS. You cannot expect it to provide transport security or durable
storage: TLS, certificate verification and redirects are the app's `HTTPTransport` (its
`URLSession`), and the refresh token's storage is the app's `TokenStore` (the Keychain).
Those halves are in the apps' own SECURITY.md. Nor does the package enforce the service's
rules: hiding a control from a role is a courtesy, and the service authorises every
request.

## Threat model

| actor | what they can do | what the package does about it |
| --- | --- | --- |
| Another app on the device | Receive or inject the sign-in callback through the app's URL scheme | PKCE with S256: an intercepted authorization code is useless without the verifier, which stays in the process (`PKCE.swift`); Sign in with Apple binds Apple's identity token to this attempt: Apple signs the SHA-256 of a fresh nonce, and the raw nonce goes to the service, which checks the two match (`AppleNonce.swift`) |
| A hostile or compromised server response | Send data of an unexpected shape, or a URL meant to send the signed-in member elsewhere | Typed `Codable` decoding into `DistrictModel` values, and the single `ApiError` for anything else; the scheduling hand-off address is refused unless it is `https` on the API's own host (`SchedulingHandoffClient.swift`) |
| A thief replaying a refresh token, or a race between two requests | Present a spent refresh token, or get two refreshes in flight | One `TokenRefreshCoordinator` per process coalesces concurrent callers onto one refresh, records the token in flight before sending it, and saves the successor before using it |
| A value that reaches a URL (an id, a search term) | Add a path segment or a query parameter | `ApiURL` and `ApiRequestDescriptor` build every URL from typed segments and percent-encode each, so a value cannot open a new segment or parameter |
| A live socket message | Claim to be about another workspace, or be malformed | `TelemetryConnection` delivers only envelopes for its own workspace and drops anything else unread |
| Someone who can push to the repository, or who tampers with a tag | Point a release tag at code that was not released | Tags are protected against moves and deletion; from the next release on they are signed with gitsign by the Release workflow under its own OIDC identity, and the README says how to verify that identity |
| A retry, a double tap or a lost answer | Bill something twice (a message, a model run, a dial) | `ApiClient` never resends a request: not on a 401, not on a 5xx, not on a timeout |

## Trust boundaries

1. **The package and the app.** The app is trusted to implement the protocols faithfully:
   `HTTPTransport` (TLS, certificates, redirects), `TokenStore` (the Keychain),
   `CallEngine` (the media SDK), `TelemetrySocketTransport` and `LiveClock`.
2. **The package and the service.** Every response is untrusted until decoded into a typed
   value; an address in a response is checked before a browser opens it.
3. **The package and the browser.** Sign-in and hand-offs leave the process; their answers
   come back through a URL scheme that another app can register.
4. **The repository and a release.** A release tag is made and signed by
   `.github/workflows/release.yml` on `main`, and each app pins it `exact:`.
5. **Memory and storage.** The access token never leaves memory; the refresh token crosses
   into the app's `TokenStore` only.

## Secure design principles applied

- **Least privilege.** The package imports only Foundation (CI greps for any other
  framework), holds no secret of its own, starts nothing, and asks for no entitlement. The
  access token is never persisted, because it buys nothing on disk. CI starts read-only
  (`permissions: contents: read` at the top of `.github/workflows/ci.yml`) and reads no
  secret.
- **Fail closed.** A response that does not decode is an `ApiError`, never a partial value.
  A hand-off address that is not `https` on the API's host is refused rather than opened.
  A refresh interrupted mid-way leads to a clean sign-in instead of a token that may be
  spent.
- **Complete mediation.** Every request goes through the one `ApiClient`, every URL through
  `ApiURL`, every refresh through the one coordinator, and every live message through the
  connection's workspace check.
- **Economy of mechanism.** One HTTP seam, one error type, one refresh coordinator, one
  external dependency (swift-crypto, for SHA-256), pinned `exact:`.
- **Separation of privilege between core and app.** What needs the platform's security
  frameworks lives in the app behind a protocol, so the core is tested in full on Linux and
  the platform code stays small.
- **Open design.** The package, its tests and the recorded responses it is tested against
  are public.

## Common weaknesses countered

Mapped to the CWE Top 25 and the OWASP Top 10 where they apply to a client library.

| weakness | how it is countered | where it is tested |
| --- | --- | --- |
| Authorization code interception (CWE-294, CWE-345) | PKCE S256, checked against vectors from the service's own implementation | `Tests/DistrictAuthCoreTests/PKCEVectorTests.swift`, `PKCETests.swift` |
| Replay and races on rotating refresh tokens (CWE-294, CWE-362) | One coordinator, coalesced callers, the in-flight marker written before sending | `Tests/DistrictAuthCoreTests/TokenRefreshConcurrencyTests.swift`, `TokenRefreshQuitTests.swift`, `TokenRefreshStoreBoundaryTests.swift` |
| Insecure storage of credentials (CWE-922, CWE-312) | The access token in memory only; the refresh token only through `TokenStore` | `Tests/DistrictAuthCoreTests/TokenRefreshStoreBoundaryTests.swift`, `FreshInstallTokenStoreTests.swift` |
| Injection into URLs (CWE-74, CWE-88) | Typed segments, each percent-encoded, through `ApiURL` | `Tests/DistrictNetworkTests/ApiURLTests.swift`, `ApiPathTests.swift` |
| Open redirect to a foreign host (CWE-601) | The hand-off address must be `https` on the API's own host | `Tests/DistrictNetworkTests/SchedulingHandoffClientTests.swift` (`aForeignHostIsRefusedEvenOverHttps`, `aNonHttpsAddressIsRefused`) |
| Improper input validation and deserialization of untrusted data (CWE-20, CWE-502) | Typed `Codable` decoding with one normalised error; recorded service responses decoded, re-encoded and compared key for key in the tests | `Tests/ContractFixtureTests/`, `Tests/DistrictNetworkTests/ApiErrorNormalizerTests.swift` |
| Cross-workspace data exposure (CWE-200) | Live envelopes for another workspace are discarded | `Tests/DistrictLiveTests/TelemetryConnectionTests.swift` |
| Duplicate side effects (CWE-837) | `ApiClient` never retries; a 401 is reported with the refused token and not resent | `Tests/DistrictNetworkTests/ApiClientFailureReportingTests.swift` (`testA401ReportsTheExactBearerAndIsNotResent`) |
| Memory safety (CWE-787, CWE-416) | Swift 6 language mode with complete strict concurrency checking; the one shared mutable store is behind a lock | The compiler |
| Secrets in the repository (CWE-798) | gitleaks over the whole history on every push and pull request | `.github/workflows/ci.yml` (`gitleaks`) |

CodeQL analyses the Swift library targets (`codeql-swift.yml`) and the workflows
(`codeql.yml`), and zizmor checks the workflows on every push and pull request.
