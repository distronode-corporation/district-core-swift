# Changelog

All notable changes to this package are recorded here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [7.0.0-beta.2] - 2026-10-14

The catalogs in Canadian French, for testing French in the iOS and Mac apps, and the
scheduling formatters' French dates and times. English is byte-identical to
7.0.0-beta.1, and nothing is French until an app sets `L10nRuntime.locale`.

### Added

- `AccountSettingsResponse` (`GET /api/settings`: the profile with its stored `locale`, nil
  for "never chosen", and the first workspace's plan and region), read by the new
  `AccountSettingsRepository.loadSettings()` through `DistrictEndpoints.accountSettings()`
  and the new `EndpointID.accountSettings`. `saveLocale` now decodes the route's answer as
  `AccountSettingsSaveResponse`; its result is unchanged.
- An optional `currency` on `BillingSubscription` and `BillingInvoice`, ahead of the server
  sending it. Today's bodies omit it and decode as before.
- Twenty-one contract fixtures from monorepo 49019be80, all gated by the strict decoder:
  number configure, release, lookup and provider status, SIP trunks, Verify, A2P and
  toll-free verification, contact blocking, account settings, and the persona options in
  French.

### Changed

- `contracts/i18n/wire-vocabulary.json` from monorepo 49019be80: `WireCategory` has 39
  cases, up from 31 (number status, A2P campaign type and registration status, toll-free
  verification status, SIP trunk status, scheduling webhook delivery status, host roles and
  question types), with their labels. A `switch` over `WireCategory` without a `default`
  needs the new cases. No existing label changed.

- `contracts/i18n/wire-vocabulary.json` from monorepo 46e1740: `WireCategory` has 31 cases,
  up from 11 (Desk tickets, knowledge documents, workflows, numbers, meetings, message
  delivery, contact research, billing and messaging accounts), with their labels, and
  `WireLabel.placeholder` knows `"No answer, no conversation took place."`. A `switch` over
  `WireCategory` without a `default` needs the new cases. No existing label changed, and
  an unknown value of an existing category reads as before.
- The catalogs carry their reviewed Canadian French (fr-CA, #20): 562 entries across
  `l10n/core.toml`, `countries.toml`, `api_errors.toml` and `wire.toml`, so
  `L10nRuntime.isFrenchComplete` is true. The language shown stays the app's choice
  (`L10nRuntime.locale`), and the apps keep French off.

### Fixed

- The scheduling formatters write French dates and times the way the website does
  (`contracts/i18n/format-vectors.json`), where they filled the French sentence with the
  English pieces. English output is unchanged.
  - The first of a month is `1er` (`1er août 2026`, not `1 août 2026`) in
    `SchedulingHoursFormat.formatOverrideDate`, `SchedulingBookingFormat.bookingDateTime`,
    `SchedulingOverviewSummary.bookingWhen` and `SchedulingDeveloperFormat.stamp`.
  - The developer stamp is 24-hour with no meridiem: `12 sept. 2026, 15 h 04`, and
    `9 h` on the hour, not `12 sept. 2026, 03 h 04 PM`.
  - `SchedulingClock.clock` and `SchedulingOverviewSummary.displayTime` read `9 h 05`
    and `9 h` rather than `9:05` and `9:00`, so the bookings table, the register and the
    working hours windows do too.
  - `SchedulingHoursFormat.formatOverrideDates` says the year once in a French range
    inside one year (`24 déc. à 26 déc. 2026`); it looked for the English
    `, 2026` and kept both years.
  - New: `L10nFormat.dayOfMonth(_:locale:)` and `L10nFormat.frenchClock(hour:minute:)`,
    which `L10nFormat.date` and `time` now share with them.
- `CallNarrative` treats the no-answer summary as absent in both spellings: the comma the
  LiveKit webhook writes now (`"No answer, no conversation took place."`) and the em dash
  that rows written before the change still hold. Without it, a new unanswered call showed
  the sentence as its AI summary. `WireLabel.placeholder` labels both spellings, and the
  new `WireLabel.spellings(ofPlaceholders:)` adds a placeholder's earlier spellings from
  the vocabulary's `aliases`. `CallNarrative.placeholders` has 7 members, up from 6.

## [7.0.0-beta.1] - 2026-10-13

The core's text, ready for Canadian French: every sentence the core writes comes from a
catalog. A major release (see Changed): every English string and format the core produces
is byte-identical to 6.0.0, every request carries one new header, and nothing is French
until an app sets `L10nRuntime.locale`, which no 7.x app does.

### For the apps

What the iOS and Mac apps absorb when they move to this version:

- `ApiError.http` is `http(status:message:code:)`. Constructing it without `code` still
  compiles; a pattern binding two values (`case let .http(a, b)`) needs a third, and an
  error with a code no longer equals one without.
- To show errors in the reader's language, read `localizedMessage` instead of `message`,
  and show the screen's own sentence when it is nil. `ApiError.code` and
  `ApiErrorCode.header` are new.
- `import DistrictL10n`: set `L10nRuntime.locale` at launch and whenever the device
  language changes, from `DistrictL10n.locale(fromPreferred:)`. Keep it `.en` until the
  app's 3.0 turns French on.
- `L10nFormat` (money, dates, times, durations, numbers, percentages, lists, the calendar's
  words), `ApiErrorText` (the error code sentences) and `WireLabel` with `WireCategory`
  (labels for statuses, roles, regions and the server's placeholders) are there for the
  apps' own screens.
- `AccountSettingsRepository.saveLocale(_:)` writes the language to the account; unused
  until 3.0.
- Every request sends `Accept-Language` (`en` until French is on).
- `DialEntry.callingCodes`, `SchedulingClock.monthNames`,
  `SchedulingHoursFormat.weekDayNames`, `SchedulingSettingsFormat.settingsTabLabels` and
  `notificationGroups`, and `SchedulingDeveloperFormat.tabLabels` and `mcpKeyPlaceholder`
  are computed rather than stored. Their English is the same and reading them compiles
  unchanged.

### Added

- A new module, `DistrictL10n`, that every other module but `DistrictAuthCore` and
  `DistrictLive` now depends on. It has no resources and uses no Foundation localization
  API, so Linux and Darwin behave alike.
  - `L10nLocale` (`en`, `frCA`), with `languageTag` (`en`, `fr-CA`) and `settingsValue`
    (`en`, `fr`). `L10nRuntime.locale` is the language the core writes in: English until
    the app sets it; `L10nRuntime.withLocale(_:_:)` and the task-local `scoped` override it
    for a scope. `L10nRuntime.isFrenchComplete` is false until every entry has reviewed
    French.
  - `locale(fromPreferred:)` (call it as `DistrictL10n.locale(fromPreferred:)`): the first
    tag whose language the core speaks decides, and any French (`fr-FR`, `fr-BE`, `fr-CH`)
    is Canadian French; a list with neither gives English.
  - `L10nFormat`: money (`money`, `isoAmount`, `moneyOrBare`, with `MoneyDisplay`), dates
    and times in a named IANA zone (`date` with `DateStyle`, `time`, `dateTime`),
    durations (`minutesSeconds`, and the wire's `callDuration`), numbers (`integer`,
    `number`, `count`), percentages (`percent(ratio:)`), lists (`list`: `A, B and C`,
    `A, B et C`) and the calendar's words (`monthAbbreviation`, `monthName`,
    `weekdayName`, `weekdayAbbreviation`, `meridiem`). Hand-written tables, held byte for
    byte to the website's `contracts/i18n/format-vectors.json` in both languages.
  - `ApiErrorText.sentence(for:items:)`: the sentence for each of the 140 API error codes
    in the active language, generated from `contracts/i18n/api-errors.json`, and
    `ApiErrorText.header` (`X-Distronode-Error-Code`).
  - `WireLabel.label(_:_:)`, `regionLongName(_:)` and `placeholder(_:)` with
    `WireCategory`: labels for the enumerated values and the server's placeholder strings
    in `contracts/i18n/wire-vocabulary.json`. An unknown value reads as a localized
    generic label, never the value humanized.
- The catalogs, `l10n/core.toml`, `l10n/countries.toml`, `l10n/api_errors.toml` and
  `l10n/wire.toml` (432 entries, no French yet), and `scripts/gen-l10n.py`, which writes
  the last two and every generated Swift file from them. The vendored catalog tools are in
  `tools/l10n/`; CI fails on a stale generated file, a non-canonical catalog or a broken
  French rule.
- `ApiError.code`: the refusal's error code, from the body's `code` or else the
  `X-Distronode-Error-Code` header (the body wins, as on the website), and
  `ApiError.localizedMessage`: `message` in English, exactly as before; in French the
  code's catalog sentence, the core's own refusal as written (an empty file, a blank
  draft: catalog text already in French), and nil only for a server's sentence with no
  code this build knows, so the screen shows its own. `ApiErrorCode.header`.
  `RawResponse.errorCodeHeader`, and `ApiErrorNormalizer.apiError(statusCode:body:headerCode:)`.
- `AccountSettingsRepository.saveLocale(_:)` and `DistrictEndpoints.saveLocale(_:)`:
  `POST /api/settings` with `{"profile":{"locale":"en"|"fr"}}`. Unused until the apps' 3.0.
- Contracts: `contracts/i18n/` (`api-errors.json`, `wire-vocabulary.json`,
  `format-vectors.json` and their README), copied unchanged from the service.

### Changed

- ⚠️ Source-breaking: `ApiError.http` gains a third associated value,
  `http(status:message:code:)`. Constructing it without `code` still compiles (it defaults
  to nil), but a pattern that binds two values (`case let .http(status, _)`) needs three,
  and two errors that differ only by code are no longer equal. That makes this release a
  major version.
- Every request `ApiClient` and `NativeAuthClient` send carries `Accept-Language`: the
  resolved language's tag, `en` until an app turns French on.
- The core's display text comes from the catalogs, in the active language: the 136 calling
  code places (`DialEntry.callingCodes`, now computed), the scheduling formatters' labels
  and sentences, the help desk's and the inbox's own refusals, the routing rule
  vocabularies' labels and the Voice Studio residency line. Tables that were stored
  (`SchedulingClock.monthNames`, `SchedulingHoursFormat.weekDayNames`,
  `SchedulingSettingsFormat.settingsTabLabels` and `notificationGroups`,
  `SchedulingDeveloperFormat.tabLabels` and `mcpKeyPlaceholder`) are now computed
  properties with the same English. The scheduling formatters' month, weekday and AM/PM
  tables moved into `L10nFormat`.

## [6.0.0] - 2026-10-07

The second factor after native Sign in with Apple. A major release (see Changed). Every
request 5.0.0 could make is byte-identical; what is new is one answer to the Apple exchange
and one route.

### Added

- `POST /api/auth/native/apple` now answers `401 mfa_required` with a single-use ticket when
  the account has an authenticator enrolled (the service's S152, live since 2026-10-06).
  `NativeAuthClient.exchangeAppleIdentityToken(_:)` reads it as the new
  `CodeExchangeResult.mfaRequired(NativeMfaChallenge)` (the ticket, and its expiry parsed by
  `WireInstant`); any other 401 stays `transportFailure`, and the PKCE exchange never
  produces the case.
- `NativeAuthClient.submitMfaCode(_:)` posts `NativeMfaRequest` (`mfaTicket`, `code`,
  `deviceId`, `deviceName` omitted when nil, `platform`) to `POST /api/auth/native/mfa` and
  answers `NativeMfaResult`: `success` with the unchanged five-key grant, `invalidCode`
  (401: wrong code or locked account, the ticket stands), `ticketRejected` (400: expired,
  spent, another install or the account changed; start again from the Apple sheet),
  `rateLimited` (429) or `transportFailure`.
- `NativeMfaChallenge.isExpired(at:)`, false when the expiry could not be read.
- In `DistrictModel`: `NativeMfaRequiredResponse`, the 401's five keys.
- In `DistrictAuthCore`: `NativeMfaCode`, the shape check the apps run before sending a code
  (six ASCII digits for an authenticator code; a recovery code of 8 to 64 characters that is
  not six digits, sent upper-cased), mirroring the service's routing by shape, and
  `authenticatorInput(_:)` for filtering a field as it is typed.
- Contracts: `contracts/mobile/` gains the service's two new fixtures (166 files, was 164),
  `district-native-apple-mfa-required.json` and `district-native-mfa.json`, both gated
  (`NativeMfaRequiredResponse`, and `NativeTokenResponse`, which is the first recorded native
  grant). `ContractFixtureTests` now depends on `DistrictAuthCore`, and
  `DistrictNetworkTests` on `ContractGateSupport` so the client tests read the recorded bytes.

### Changed

- ⚠️ Source-breaking: `CodeExchangeResult` gains a case, so an exhaustive `switch` over it
  needs `.mfaRequired` (both apps' `AppleSignInController.exchange` have one). That makes
  this release a major version.

## [5.0.0] - 2026-10-06

A major release (see Changed). Every request 4.0.0 could make is byte-identical; what is
new is the socket's outbound side.

### Added

- The live call transcript (`transcript` v1 on the telemetry socket). In `DistrictModel`:
  `TelemetryEventType` gains `transcriptSnapshot`, `transcriptSegment`, `transcriptEnded`,
  `transcriptRetracted` and `transcriptError` (and `isTranscript`);
  `TelemetryEnvelope.transcriptEvent` reads their `data` into `TranscriptEvent`
  (`TranscriptSnapshotData`, `TranscriptSegmentData`, `TranscriptEndedData`,
  `TranscriptRetractedData`, `TranscriptErrorData`, with `TranscriptSegment`), refusing a
  `v` other than 1 and data whose `callId` disagrees with the envelope's. The speaker, end
  reason, retract reason and error code are open vocabularies (`.other` keeps an unknown
  name), unknown `data` keys are ignored, and a segment's text is left out of every
  printed form. `TranscriptClientOp` writes the three client ops
  (`transcript.subscribe`, `transcript.unsubscribe`, `socket.mode`), refusing a call id
  outside `[A-Za-z0-9_-]{1,64}`.
- In `DistrictLive`: `TelemetryConnection` (and `TelemetryConnectionRunner`) keep a set of
  transcript subscriptions and send them again on every open, renewals included, after a
  `socket.mode` when built with `broadcast: false`; new events
  `subscribeTranscript`/`unsubscribeTranscript`/`resubscribeTranscript`, a new command
  `send`, and the runner's three matching methods. `TranscriptReducer` is the contract's
  client algorithm for one call as a pure state machine, following the contract's §4.6
  and its §4.12 clarifications: a high-water mark per epoch plus the set of missing seqs
  below it (a late frame fills its gap, anything else at or below the mark is a duplicate;
  the missing set is kept as ranges, so a jump of any size is tracked exactly), revisions,
  `(epoch, index)` order, a re-subscribe after a gap lasts 2 s with one heal in flight per
  call, snapshots whose parts arrive back to back with the same header (a broken one is
  asked for again once its last part is in) and which close every older epoch, retraction
  with tombstones (counted only when it carries `epoch` with `seq`), and the end:
  `call_ended`, `handed_off` or an unknown reason is final and fetches the full transcript
  with backoff; `agent_error` is the new `LiveTranscriptPhase.reconnecting` until a fresh
  assistant's epoch or the call's end; a snapshot's `endedReason` says the same (§4.12 Q9),
  so a fresh subscribe after `agent_error` is reconnecting too. A snapshot with no epoch
  follows an `all: true` purge (Q12): state and missing set are cleared, and the next frame
  of each epoch sets its baseline. `not_live` is final for its subscribe:
  `callShownInProgress(atMilliseconds:)` (a call-status signal that shows the call in
  progress, at most once per 30 s per call, Q10) is the only way to subscribe again, as the
  new `TranscriptCommand.subscribe`; after the 120 s eviction it is the path after the call
  (Q11). Only an error whose `op` is exactly
  `transcript.subscribe` changes anything.
- `TranscriptSnapshotData` carries `endedReason` (null while live, absent from an older
  server and then nil), written back as an explicit null.
- `TranscriptRetractedData` carries `epoch` beside `seq` (both null from the website),
  written back as explicit nulls; its initialiser takes the contract's key order.
- Tests: the service's own fixtures for the five events (six frames, an interim segment
  among them) in `Tests/TranscriptFrames/`, copied byte for byte from its
  `contracts/mobile/` set. They follow the contract revision with §4.12 Q1 to Q17 (the
  retraction's `epoch`, no empty opening snapshot, the snapshot's `endedReason`), and
  `TranscriptFrameTests` puts each through the strict gate and checks §4.12's invariants
  on them.
- Contracts: `contracts/mobile/` gains the service's seven new fixtures (164 files, was
  157): the six `telemetry-event-transcript-*` events and `district-telemetry-token.json`
  (the desktop file, byte for byte). `ContractFixtureTests` gates all seven, the events as
  the envelope and again as their typed `data`, with eight allowed-null paths (201, was
  193), and `TranscriptFrameTests` asserts its frames match the vendored copies byte for
  byte.

### Changed

- ⚠️ Source-breaking: `TelemetryEventType` gains five cases, so an exhaustive `switch`
  over it needs them (district-macos has none; `DesktopRingGate`'s own is updated).
  `TelemetrySocket` gains a requirement, `send(_:)`, which district-macos's
  `URLSessionTelemetrySocket` must implement; `TelemetryConnectionEvent` and
  `TelemetryConnectionCommand` gain cases. That makes this release a major version.
- CI's floor on the number of tests run rises from 1850 to 1980.

## [4.0.0] - 2026-10-05

A major release for one reason: `DistrictSection` gains a case (below). Every request
3.1.0 could make is byte-identical.

### Added

- District Studio links. `AppLinkResolver` maps `/dashboard/district/studio` (the web's
  section for the AI receptionist's settings since 2026-10-04) to the new
  `DistrictSection.studio`, and `/dashboard/district/studio/<area>` to it with the area
  carried: `StudioArea` names the pages the apps draw (`persona`, `voice`,
  `call-handling`, `skills`, `knowledge`), read back through
  `AppLinkDestination.studioArea`. A Studio page outside that list (`integrations`,
  `video`, anything else) resolves to `openInBrowser`. A Studio destination waits for a
  workspace.

### Changed

- Contract fixtures only, no change to the package: `district-enrich-disabled.json` and
  `district-voice-studio.json` mirror the service's new copies. The enrichment refusal now
  names District Studio → Integrations, and the Voice Studio read's `heading` is "Voice",
  the name of the web's District Studio page.
- ⚠️ Source-breaking: `DistrictSection` gains a case, so an exhaustive `switch` over it
  (district-ios's `AppLinkRouting`) needs a `.studio` arm when it adopts this release;
  district-macos has no such switch and needs only the pin. That
  makes the next release a major version.
- Repository only, no change to the package: the README carries the OpenSSF Scorecard
  badge, links district-macos and drops the private-era CI note; `.github/SUPPORT.md` says
  where questions and bugs go; the issue chooser links the README, Discussions and private
  vulnerability reporting; CodeQL runs gain a workflow-level `concurrency` group; and a
  new `dependency-review.yml` checks the dependencies a pull request adds.

## [3.1.0] - 2026-10-04

A minor release: everything is additive, and every request 3.0.0 could make is
byte-identical.

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
- The read's templates for text a client builds itself (`meterAbout`, `meterAtLeast`,
  `meterNone`, `meterPartial`, `numberGrouping`, `basedOnOne`, `basedOnMany`) on
  `VoiceStudioLabels`, and `VoiceStudioText`, which fills them: an unsaved edit's meter
  headline, a bare median and the "Based on" line follow the portal language
  (`VoiceStudioSession.basedOn`). An unsaved edit's "some steps are not measured" note is
  now `meterPartial`.
- `VoiceStudioRefit`: after a persona language save, a chain of the member's own that no
  longer fits is moved to the nearest offered models speaking the language, saved and read
  back (the web's `conformEngineMix`, as district-linux does it).

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

[Unreleased]: https://github.com/distronode-corporation/district-core-swift/compare/7.0.0-beta.2...HEAD
[7.0.0-beta.2]: https://github.com/distronode-corporation/district-core-swift/releases/tag/7.0.0-beta.2
[7.0.0-beta.1]: https://github.com/distronode-corporation/district-core-swift/releases/tag/7.0.0-beta.1
[4.0.0]: https://github.com/distronode-corporation/district-core-swift/releases/tag/4.0.0
[3.1.0]: https://github.com/distronode-corporation/district-core-swift/releases/tag/3.1.0
[3.0.0]: https://github.com/distronode-corporation/district-core-swift/releases/tag/3.0.0
[2.0.0]: https://github.com/distronode-corporation/district-core-swift/releases/tag/2.0.0
[1.0.0]: https://github.com/distronode-corporation/district-core-swift/releases/tag/1.0.0
