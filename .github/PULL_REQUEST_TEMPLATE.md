<!-- Thanks for the contribution. Delete any section that genuinely does not apply. -->

## What changed

<!-- One or two sentences. The diff says what; this says it in words. -->

## Why

<!-- The problem, not the patch. If it fixes an issue, link it (Fixes #123). If an app
     needs this change, link the app's pull request or issue. -->

## How it was tested

<!-- Commands you actually ran, and what they said. "Should work" is not a test.
     CI runs the same gates; see CONTRIBUTING.md for the full list. -->

- [ ] `swiftformat --lint .` (SwiftFormat 0.63.0) and `swiftlint --strict` (SwiftLint 0.65.1)
- [ ] `swift test --enable-code-coverage`, then `ci/coverage-gate.sh`
- [ ] `python3 scripts/check-public-hygiene.py`
- [ ] `Package.resolved` is not part of this change, or the change is a reviewed
      dependency bump

## Public API

<!-- Does this add, change or remove a public type or member? If so, say which, and add
     a line under `Unreleased` in CHANGELOG.md. A source-breaking change needs a major
     version. -->

## Anything a reviewer should know

<!-- A decision you were unsure about, something you deliberately left out, or what you
     could not test. Saying so is useful, not a problem. -->
