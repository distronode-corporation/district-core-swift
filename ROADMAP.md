# Roadmap

The near-term plan for District Core for Swift. This repository has no open issues, so the list
is taken from the repository's own unfinished items, each named with where it comes from. It has
no dates: an item is done when the change that does it is merged and released, and it then
leaves this list for [CHANGELOG.md](CHANGELOG.md). Anything here can change; open an issue to
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

## How the project is run

Who decides what goes on this list, and how, is in the organization's
[GOVERNANCE.md](https://github.com/distronode-corporation/.github/blob/main/GOVERNANCE.md).
