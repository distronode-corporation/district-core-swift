/// The exact paths in the desktop fixtures permitted to hold an explicit `null`.
///
/// ⛔ THE SAME RULES AS THE MOBILE REGISTER (`AllowedExplicitNulls.swift`): exact
/// paths, no wildcards, each a decision about a nullable column. Kept apart from it
/// because that register's total is asserted (`ContractManifest.expectedAllowedNullPaths`)
/// against the MOBILE set, and a desktop entry there would move a mobile number.
///
/// ⚠️ EVERY NULL HERE IS INSIDE `data`, WHICH IS CARRIED AS `WireJSON` AND RE-ENCODES A
/// NULL AS A NULL. So an entry here buys only the no-nulls exemption; the key-set
/// comparison still holds at every one of these paths, because the key survives the
/// round trip. That is the property that lets the gate walk an unmodelled blob.
///
/// The columns, all on `Call`, all nullable in the schema, and all sent as `null`
/// rather than omitted because the publisher spreads the whole Prisma row:
///
///   analysis, disposition, sentiment   The post-call pipeline's output; null until it ran.
///   contactId                          No Contact row matched the caller.
///   divertedFrom                       The call was not forwarded to this number.
///   endedAt                            The call has not ended.
///   followUpEmail, followUpSMSBody,
///   followUpSentAt                     No follow-up was sent.
///   liveTranscript, transcript,
///   summary                            Nothing transcribed or summarised yet.
///   recordingUrl, storedRecordingKey   No call is recorded in any region.
///   roomName, to, startedAt            An outbound call before its leg connected.
///   transferStatus, transferReason     No transfer was attempted.
enum DesktopAllowedNulls {
    static let byFixture: [String: Set<String>] = [
        "telemetry-event-call-ended-row.json": [
            "$.data.divertedFrom",
            "$.data.recordingUrl",
            "$.data.storedRecordingKey",
            "$.data.transferReason",
            "$.data.transferStatus",
        ],
        "telemetry-event-call-started.json": [
            "$.data.analysis",
            "$.data.disposition",
            "$.data.divertedFrom",
            "$.data.endedAt",
            "$.data.followUpEmail",
            "$.data.followUpSMSBody",
            "$.data.followUpSentAt",
            "$.data.liveTranscript",
            "$.data.recordingUrl",
            "$.data.sentiment",
            "$.data.storedRecordingKey",
            "$.data.transcript",
            "$.data.transferReason",
            "$.data.transferStatus",
        ],
        "telemetry-event-call-updated.json": [
            "$.data.analysis",
            "$.data.contactId",
            "$.data.disposition",
            "$.data.divertedFrom",
            "$.data.followUpEmail",
            "$.data.followUpSMSBody",
            "$.data.followUpSentAt",
            "$.data.liveTranscript",
            "$.data.recordingUrl",
            "$.data.roomName",
            "$.data.sentiment",
            "$.data.startedAt",
            "$.data.storedRecordingKey",
            "$.data.summary",
            "$.data.to",
            "$.data.transcript",
            "$.data.transferReason",
            "$.data.transferStatus",
        ],
    ]

    /// ⚠️ ASSERTED, so an entry added or removed is a reviewed number change rather
    /// than a silent widening.
    static let expectedCount = 37
}
