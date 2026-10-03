# Contributing to District Core for Swift

Thanks for helping. The [README](README.md) covers what the package is, its modules and
how to build it. This file is the rules a change has to meet.

## Upstream first

This package is the shared core of District AI for iOS and for macOS. A change to the
core lands **here first**, in its own pull request with its tests. Once it is released
(a version tag), each app adopts it by bumping its exact pin in a pull request of its
own. Do not patch a copy of the core inside an app: neither app carries one.

If a change needs both sides (a new model here and a screen that uses it in an app),
open the core pull request first and link it from the app's.

## The inner loop

```sh
swift test
```

No simulator, no network and no account, on macOS or Linux. `swift test --filter
<TestClass>` runs one class.

## The whole local gate

This is what CI's `verify` and `hygiene` jobs run, in order:

```sh
swiftformat --lint .                          # SwiftFormat 0.63.0
swiftlint --strict                            # SwiftLint 0.65.1
swift test --enable-code-coverage
ci/coverage-gate.sh
python3 scripts/check-public-hygiene.py
```

CI also greps the sources for Darwin-only imports, checks `Package.resolved` and counts
the tests that ran; all three are described below. It runs `gitleaks git .` (gitleaks
8.30.1) over the full history too, with `.gitleaks.toml`, and `zizmor` over the
workflows; run them locally if you have them.

## Rules CI enforces

**Style.** SwiftFormat and SwiftLint, at the versions above, from the repository root.
Use exactly those versions: the two tools disagree by default about some constructs and
are configured to agree, and another version can put them back at odds. SwiftLint runs
with `--strict`, so a warning is a failure, and there is no baseline file.

**Tests and coverage.** A change in behaviour comes with a test that fails without it.
Line coverage is 100%, and `ci/coverage-gate.sh` holds every module and the total there:
a line a test can reach gets a test, and a line nothing can reach is deleted, with a
comment at the site saying why. Floors never go down.

**Foundation only.** No `import` of UIKit, AppKit, SwiftUI, Security,
AuthenticationServices, CallKit, PushKit or LiveKit anywhere under `Sources` or `Tests`,
including inside `#if canImport(...)`. Declare a protocol here and implement it in the
apps (see `HTTPTransport`, `TokenStore` and `CallEngine`). This is what keeps every line
of the core tested on Linux.

**`Package.resolved` pins only swift-crypto and swift-asn1.** Resolving an app's packages
in Xcode with this package checked out locally can write the app's pins into this file.
Restore it with `git checkout -- Package.resolved` and never commit that write.

**Contract fixtures are not edited here.** `contracts/mobile/` and `contracts/desktop/`
mirror the District AI service's own fixture sets and are updated by pull request when
the service changes them; a pull request that edits one by hand will not be merged. If a
fixture looks wrong, or a model and the service disagree about a response, open an
issue. A model change that needs a new or different fixture waits for the fixture to
arrive from the service.

**Test bundles must discover their tests.** CI counts the tests that ran and fails below
the floor set in `.github/workflows/ci.yml` (1810). It sits a little below the current
count and is a ratchet: a change that adds many tests may raise it, and a change that
deletes tests on purpose lowers it in the same commit and says why.

**Public hygiene.** No em or en dashes (use commas, periods or parentheses), no internal
host names and no GitLab URLs, anywhere outside `contracts/`. A string that must hold a
dash at run time spells it as an escape (`"\u{2014}"`).

## Pull requests

Pull requests run [`.github/workflows/ci.yml`](.github/workflows/ci.yml), and all of it
must be green. The workflow reads no secrets, so a pull request from a fork runs exactly
the same checks; GitHub asks a maintainer to approve the first run for a first-time
contributor.

Conventional Commits are not required. What is required is that the message says **why**:
the diff already says what. Name what was wrong and how you know.

Changes to public API are noted in [CHANGELOG.md](CHANGELOG.md) under `Unreleased`.

## Releases

Contributors do not cut releases. A maintainer tags a version (`1.0.0`, no `v`), following
Semantic Versioning: a source-breaking change to a public type is a major version.

## Reporting bugs and asking questions

Use the bug report form for a bug. For anything security-relevant, do not open an issue;
see [SECURITY.md](SECURITY.md).

## Licence of contributions

By contributing you agree that your contribution is licensed under the Apache License
2.0, as section 5 of [the licence](LICENSE) provides. There is no CLA and no sign-off
requirement.
