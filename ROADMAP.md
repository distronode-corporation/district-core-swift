# Roadmap

The near-term plan for District Core for Swift. This repository has no open issues, so the list
is taken from the repository's own unfinished items, each named with where it comes from. This roadmap covers the next twelve months, to November 2027. Items have no dates of their own:
an item is done when the change that does it is merged and released, and it then leaves this
list for [CHANGELOG.md](CHANGELOG.md). Anything here can change; open an issue to
discuss an item or to propose a new one.

## Near term

- **The first signed release.** The Release workflow that signs each tag with gitsign is merged
  and listed under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md), together with the API error
  codes synced from the service since 8.6.0. Tags up to and including 8.6.0 are not signed
  (README, "Verify a release"). The plan is to ship all of it in the next release, the first
  whose tag can be checked with `gitsign verify-tag`.
- **Models for the fixtures that have none yet.** The contract gate lists, by name, the
  service's recorded responses that have no Swift model yet: the Inbox thread-assignment read,
  and three web settings areas the apps have no screen for (the agent's picture library, the
  settings calendar disconnect and the email sending domain). The list also holds the PKCE
  vectors, which are test data that `PKCEVectorTests` reads, not a response to model
  (`unimplemented` in
  [`Tests/ContractFixtureTests/ContractManifest.swift`](Tests/ContractFixtureTests/ContractManifest.swift)).
  An entry leaves that list together with its model, its endpoint and the repository method
  that decodes it, when an app needs it.

## Open questions

- **Using the apps without a District AI account.** Today the apps built on this package need a
  District AI account to sign in. Whether they can work without one, and what that would look
  like, is an open question we are asking about before building anything (README, "Without an
  account with us";
  [the discussion](https://github.com/distronode-corporation/.github/discussions/1)).

## Not planned

What the package will not do, as the README and [ARCHITECTURE.md](ARCHITECTURE.md) set it out.

- **Code that needs an Apple framework.** Every module imports only Foundation (and
  FoundationNetworking on Linux), and CI enforces it. The HTTP stack, the Keychain, the media
  SDK, the call registry and the user interface stay in each app, behind the protocols here.
- **Files on the device.** The package writes no file. The refresh token lives in the app's
  `TokenStore`, and everything else lives on the service.
- **Platform or CLDR formatters.** Numbers, money, dates and lists come from `L10nFormat`'s own
  tables, held to the website's outputs, so the text is the same on every OS version.
- **Automatic resending of requests.** `ApiClient` never resends a request; after a 401 the app
  invalidates the refused token and the next request refreshes first.
- **The District AI service.** The service the package talks to is not open source and is not
  part of this repository.

## How the project is run

Who decides what goes on this list, and how, is in the organization's
[GOVERNANCE.md](https://github.com/distronode-corporation/.github/blob/main/GOVERNANCE.md).
