# Architecture

This is the high-level design of District Core for Swift: the modules, the seams the apps
implement, how a request travels, and where state lives. What the design protects, and how,
is in [SECURITY-MODEL.md](SECURITY-MODEL.md). The module table in the [README](README.md)
says what each module holds.

## The shape: a Foundation-only core behind protocols

The package holds everything about the District AI apps that can be tested on Linux
without a simulator, a network or an account. Every module imports only Foundation (and
FoundationNetworking on Linux), and CI greps `Sources` and `Tests` to keep it that way.
What needs an Apple framework (the HTTP stack, the Keychain, the media SDK, the call
registry, the user interface) is a protocol here and an implementation in each app:

| protocol | module | what the app supplies |
| --- | --- | --- |
| `HTTPTransport` | `DistrictNetwork` | The `URLSession` adapter that sends a request |
| `TokenStore` | `DistrictAuthCore` | Durable session storage, over the Keychain |
| `CallEngine` | `DistrictCall` | The media SDK (LiveKit) that joins a call |
| `TelemetrySocketTransport` | `DistrictLive` | The WebSocket adapter for live updates |
| `LiveClock` | `DistrictLive` | Time, so the tests can run every rule without waiting |

The tests supply doubles for each, which is how the package reaches 100 percent line
coverage on Linux.

## The modules and how they depend on each other

| module | depends on |
| --- | --- |
| `DistrictL10n` | nothing |
| `DistrictModel` | `DistrictL10n` |
| `DistrictAuthCore` | `DistrictModel`, swift-crypto (SHA-256) |
| `DistrictNetwork` | `DistrictL10n`, `DistrictModel` |
| `DistrictData` | `DistrictL10n`, `DistrictModel`, `DistrictNetwork` |
| `DistrictCall` | `DistrictL10n`, `DistrictModel` |
| `DistrictLive` | `DistrictModel`, `DistrictNetwork` |

Each module is a library product, so an app links only what it uses. swift-crypto (and
swift-asn1 through it) is the one external dependency, pinned `exact:` in `Package.swift`
and recorded in the committed `Package.resolved`.

## A request, end to end

A screen in an app asks a repository in `DistrictData` (for example `InboxRepository`) for
what it shows. The repository calls `ApiClient` (`DistrictNetwork`) with an endpoint from
the endpoint table, never a hand-built path: `ApiRequestDescriptor` and `ApiURL` build
every URL from typed segments and escape each one. `ApiClient` adds the bearer token from the token
provider the app wires to `TokenRefreshCoordinator` (`DistrictAuthCore`), hands the request
to the app's
`HTTPTransport`, and turns the answer into a `DistrictModel` value: a `Codable` DTO for a
success, or the single normalised `ApiError` for anything else, a transport failure
included. The repository pages, merges or maps that value for the screen.

The refresh coordinator renews the access token shortly before it expires, one refresh at
a time per process, because the service rotates the refresh token and treats a second
presentation of one as theft. `ApiClient` never resends a request: a 401 is reported with the
exact token the service refused (`RejectedTokenHandler`), the app invalidates that token in
the coordinator, and the next request refreshes first.

Calls and live updates follow the same pattern. `DistrictCall`'s state machines take what
happened (the user answered, the engine connected, the service ended the call) and emit
`SoftphoneCommand`s for the app to carry out with its media SDK and call registry.
`DistrictLive`'s `TelemetryConnection` is a state machine for the live telemetry socket,
run by an actor over the app's socket transport; an event is a hint to read the state
again, and one that cannot be read or names another workspace is dropped unread.

## Where state lives

- **In memory**: the access token (held by `TokenRefreshCoordinator`, re-minted after a
  restart and never written to disk), the state machines' state, and whatever the
  repositories return.
- **In the app's `TokenStore`** (the Keychain): the refresh token, and the marker of a
  refresh in flight, written before the refresh is sent, so a process that dies mid-refresh
  starts the next launch with a clean sign-in instead of presenting a rotated token.
- **On the service**: everything else. The package writes no file.

## Text and formats

Every piece of display text comes from the TOML catalogs in `l10n/`, generated into
`DistrictL10n` by `scripts/gen-l10n.py`, in English or Canadian French as the app chooses
(`L10nRuntime.locale`). Numbers, money, dates and lists are formatted by `L10nFormat`'s own
tables, held byte for byte to the website's outputs in `contracts/i18n/`, rather than by a
platform formatter, so a customer reads the same text on every OS version.

## What the package is tested against

`contracts/` holds responses recorded by the District AI service's own test suite.
`ContractFixtureTests` and `DesktopContractFixtureTests` decode every fixture that has a
model, re-encode it and compare the keys at every level, against exact fixture counts, so a
field the service adds or renames fails a test here. The decoders themselves ignore
unknown fields, so an installed app keeps working when the service adds one.

## Build and release

One Swift package, one dependency graph, built with `swift build` and Xcode alike. A release
is a version tag (`8.6.0`, no `v`); each app pins it `exact:` and moves in a pull request of
its own (CONTRIBUTING.md).
