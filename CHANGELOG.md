# Changelog

All notable changes to this package are recorded here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The native Voice Studio. `VoiceStudioResponse` and its parts in `DistrictModel` decode
  `GET /api/district/workspace/persona/voice-studio` (recipes, the resolved signal chain,
  the time-to-first-word meter, the per-leg catalogue, voices and every tuning key, with
  labels already in the reader's portal language), and `EngineMix` models
  `aiPersona.engineMix` v1, its absent-when-unset keys included. `VoiceStudioKey` names the
  persona keys the Studio owns.
- `EndpointID.personaVoiceStudio`, `DistrictEndpoints.personaVoiceStudio(workspaceId:)`,
  `DistrictEndpoints.saveVoiceStudio(workspaceId:fields:keys:)` (the existing persona PATCH,
  carrying only the named keys) and `JSONValue.engineMix(_:)`, which writes a mix in the web
  Studio's exact shape.
- `VoiceStudioRepository` in `DistrictData`: the read, and a save that always reads the
  Studio back, naming the two refusals (`invalid_engine_mix`,
  `model_unavailable_in_region`) and telling a write whose re-read failed from one that
  never landed.
- The Studio's rules, ported from the web Studio with Android's client as the sibling:
  `VoiceStudioSession` (the held state and every transition), `VoiceStudioRules` (the
  preset rule, the save body, the changed keys, whether a save landed, the change count),
  `VoiceStudioRecipes`, `VoiceStudioLegEdits`, `VoiceStudioTuning` with
  `VoiceStudioNumberPath` and `VoiceStudioChoicePath`, `VoiceStudioPickers`, and
  `VoiceStudioReadout`, which shows the service's own words for any engine it described and
  assembles an unsaved edit's from the same response's measured medians, never estimating.
- `contracts/mobile/district-voice-studio.json`, the 157th mobile fixture, gated strictly
  with its explicit nulls permitted per field of a kind rather than per row.

## [3.0.0] - 2026-10-04

A major release because public API is removed (see Removed). Nothing is added, and
every request that still exists is byte-identical to 2.0.0.

### Removed

Nothing is recorded in any region, and the District AI service retired every surface
that served recordings on 2026-10-03. Each of these is now a 404 or an `unknown_op`
there, so the client code could only fail. Source-breaking, hence a major version.

- `CallsRepository.recordingURL(workspaceId:callId:)`, `DistrictEndpoints.callRecordingUrl`
  and `EndpointID.callRecordingUrl` (`GET /api/district/calls/{id}/recording`).
- `SchedulingAdminMediaRepository.recordingDownloadURL(workspaceId:recordingId:)`,
  `DistrictEndpoints.schedulingAdminDownload` and `EndpointID.schedulingAdminDownload`.
- With both redirect routes gone: `ApiClient.redirectTarget(_:)`, `RedirectTarget` and
  `RedirectEndpoints`. `HTTPTransport` keeps `followRedirects`, which the app's
  `scheduling/sso` leg still sets to false.
- Eleven `SchedulingAdminOp` cases (75 to 64): `recordings.list`, `.delete`, `.deleteAll`,
  `.consent`; `settings.storage.get`, `.patch`; `settings.notetaker.get`, `.patch`;
  `bookings.notes`, `bookings.notes.regenerate`, `bookings.transcript`. Their repository
  methods (`recordings`, `deleteRecording`, `deleteAllRecordings`, `recordingConsents`,
  `storageSettings`, `setRecordingsEnabled`, `notetakerSettings`, `setNotetakerEnabled`,
  `bookingNotes`, `regenerateBookingNotes`, `bookingTranscript`) and models
  (`SchedulingRecording`, `SchedulingRecordingList`, `SchedulingRecordingsDeleted`,
  `SchedulingRecordingConsent`, `SchedulingRecordingConsents`,
  `SchedulingStorageSettings`, `SchedulingNotetakerSettings`, `SchedulingBookingNotes`,
  `SchedulingBookingNotesRegenerated`, `SchedulingBookingTranscript`) went with them.
- `SchedulingRecordingFormat`, `SchedulingMarkdown` and `SchedulingNotesBlock` (the
  booking notes parser), `SchedulingClock.paddedClock(_:)` and
  `SchedulingSettingsFormat.recordingDescription(_:)`, which only those screens used.

### Changed

- `CallSummary.recordingUrl` stays an optional `String` and is now always null on the
  wire (the key is kept so installed apps keep decoding).
- `SchedulingSettingsFormat.settingsTabIds` and `settingsTabLabels`: the second tab is
  `assistant` ("Booking assistant") instead of `recordings` ("Recordings and notes"), as
  on the web.
- `contracts/mobile/` synced with the service (156 fixtures, was 164): the eight
  recording, storage, notetaker, booking notes and transcript fixtures are gone, and
  `recordingUrl` is null on the answered row of `district-calls.json`,
  `district-overview.json` and `district-call-detail.json`.

## [2.0.0] - 2026-10-03

A major release only because `PushTokenKind` gained a case (see Changed): every other
change is additive, and an app that passes nothing new sends exactly the bytes it sent
on 1.0.0.

### Added

- `DistrictLive`, a new library product: the desktop's live updates.
  `TelemetryConnection` is the telemetry socket's protocol as a pure state machine
  (subprotocol `distronode.telemetry.v1`; 4401 mints a new credential, 4403 stops;
  renewal a minute before expiry; reconnect backoff between 1 s and 60 s with
  jitter; a 90 s silence watchdog; a 15 s connect timeout), and
  `TelemetryConnectionRunner` performs its commands over a `TelemetrySocketTransport`
  and a `LiveClock`. `PresenceController` registers the Mac's presence
  (`kind: "desktop"`), renews it every five minutes and withdraws it on sign-out.
  `DesktopRingGate` starts a ring on `call_ringing` for this member and ends it on
  `call_ended`, on a `call_updated` the answer route would refuse, or after 30 s.
- `ClientPlatform` (`ios`, `macos`), taken with a default of `ios` by
  `CodeExchangeRequest`, `AppleNativeSignInRequest`,
  `DistrictEndpoints.registerPushToken`, `DistrictEndpoints.roomToken`,
  `PushTokenRepository` and `RoomsRepository`. Also `PushPlatform.macos` and
  `RoomIdentity.value(for:)`.
- `PushTokenKind.desktop`, the Mac's presence registration.
- `AccessClaims(jwt:)` in `DistrictAuthCore`: reads `sub`, `did` and `exp` from the
  native access token (a read, not a signature check).
- `TelemetryTokenResponse`, `TelemetryEnvelope` and `TelemetryEventType` in
  `DistrictModel`, `DistrictEndpoints.telemetryToken(workspaceId:)` and
  `ApiClient.telemetryToken(workspaceId:)` in `DistrictNetwork`.
- `DesktopContractFixtureTests`, which gates all 13 files in `contracts/desktop/`.

### Changed

- `PushTokenKind` gained a case, so an exhaustive `switch` over it outside this
  package needs a `.desktop` arm.

## [1.0.0]

### Added

- The package, extracted with its history from
  [district-ios](https://github.com/distronode-corporation/district-ios) at `0b2354b`,
  where it lived as `Packages/DistrictCore`. No API change: the modules
  (`DistrictModel`, `DistrictAuthCore`, `DistrictNetwork`, `DistrictData`,
  `DistrictCall`), their public types and their behaviour are the same as at that commit.
- `contracts/mobile/`, the mobile contract fixtures (164), moved from district-ios's
  `contracts/`.
- `contracts/desktop/`, the desktop contract fixtures (13), copied from the District AI
  service. No test reads them yet.
- CI of its own: lint, the Foundation-only import rule, tests with a count floor and
  100% line coverage, gitleaks, zizmor and a public-hygiene check, plus a macOS job
  that builds for iOS and macOS.

[Unreleased]: https://github.com/distronode-corporation/district-core-swift/compare/3.0.0...HEAD
[3.0.0]: https://github.com/distronode-corporation/district-core-swift/releases/tag/3.0.0
[2.0.0]: https://github.com/distronode-corporation/district-core-swift/releases/tag/2.0.0
[1.0.0]: https://github.com/distronode-corporation/district-core-swift/releases/tag/1.0.0
