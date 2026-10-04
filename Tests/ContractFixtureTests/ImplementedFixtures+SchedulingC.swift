import DistrictModel
import Foundation

// The scheduling admin's settings, developer and upload rows, gated against the
// ten fixtures they model.
//
// ⛔ SPLIT OUT BECAUSE `ImplementedFixtures.swift` IS AT ITS 500-LINE CEILING, the
// same reason `+MessageThread.swift`, `+SchedulingAdmin.swift` and
// `+SchedulingB.swift` were. SwiftLint's `file_length` warning is an ERROR under
// `--strict`, so one line added inline reds the LINT job rather than the gate, a
// failure a long way from the change that caused it.

extension ImplementedFixtures {
    // MARK: - Settings, developer and the image upload

    /// ⛔ NINE RPC PAYLOADS PLUS ONE THAT IS NOT AN RPC PAYLOAD AT ALL, AND
    /// THE ODD ONE IS THE REASON TO READ THIS LIST RATHER THAN SKIM IT.
    /// `district-scheduling-upload.json` is the MULTIPART route's answer: it is not
    /// in the op catalog, it has no `op` name, and it arrives from
    /// `/api/district/scheduling/admin/upload`, yet it wears
    /// ``SchedulingAdminSuccess`` because that route deliberately answers the
    /// catalog's envelope, `{ok:false, failure, status}` at HTTP **200** included,
    /// so both surfaces have one failure vocabulary. Gating it here is what pins
    /// that deliberate agreement; if the upload route ever stopped matching, this
    /// entry fails and nothing else would.
    ///
    /// ⛔ TWO CONTAINER CONVENTIONS LIVE IN THESE TEN FILES AND THEY ARE NOT
    /// DERIVABLE FROM THE OP'S NAME. `apiKeys.list`, `oauth.connections.list`,
    /// `webhooks.list` and `webhooks.deliveries` use the catalog's shared
    /// `items(...)` helper, so they gate through ``SchedulingItems``; and every
    /// settings op answers a bare object with no container at all. Reading one through
    /// another's container is a missing-key decode error that presents as an
    /// outage, which is exactly the failure the strict gate turns into a named
    /// line.
    ///
    /// ⛔ THE TWO "CREATED" BODIES ARE SEPARATE TYPES FROM THEIR LIST ROWS, NOT
    /// OPTIONAL FIELDS ON THEM, AND THE GATE IS WHAT MAKES THAT SAFE RATHER THAN
    /// MERELY TIDY. `district-scheduling-api-key-created.json` carries `key`, the
    /// plaintext credential, shown once, and `-webhook-created.json` carries
    /// `secret`. Modelled as Optionals on ``SchedulingAPIKey`` and
    /// ``SchedulingWebhook``, both would ROUND-TRIP CLEANLY against the list
    /// fixtures too (a nil Optional writes an absent key), so the gate would not
    /// object and "is the secret here" would become a runtime question asked in
    /// every cell. Two types make it a compile-time question asked once.
    ///
    /// ⚠️ FOUR EXPLICIT NULLS ACROSS THREE OF THE TEN, and
    /// `AllowedExplicitNulls+SchedulingC.swift` says which columns and why. ⛔ The
    /// seven others carry NONE, checked against the fixture bytes rather than
    /// inferred from the types, and that includes the row that looks most like a
    /// candidate: the delivery that got no answer is ABSENT keys, which a nil
    /// Optional already round-trips.
    ///
    /// ⚠️ THE FIVE RECORDING, STORAGE AND NOTETAKER FIXTURES WERE RETIRED BY THE
    /// SERVER WITH THEIR OPS (2026-10-03) and left the directory in the same sync,
    /// which is what moved ``ContractManifest/expectedFixtureCount``.
    static var schedulingC: [ImplementedFixture] {
        settingsFixtures + developerFixtures
    }

    /// `me.*` and the two `settings.*` namespaces.
    ///
    /// ⛔ THE LLM SETTINGS BODY IS TINY BECAUSE THE CATALOG STRIPPED IT, NOT
    /// BECAUSE THE FORK IS. `settings.llm` answers two fields here and six more at
    /// the far end (`endpoint`, `model`, `api_key_set`, `configured`, `active`,
    /// `base_prompt`). Every one of those names an INSTANCE credential or a
    /// resource shared with other tenancies. ⚠️ So a DTO grown
    /// "to match the fork" would model keys that cannot arrive, and this gate would
    /// report them as ADDED on re-encode, which is the right failure, in the right
    /// place, for the right reason.
    private static var settingsFixtures: [ImplementedFixture] {
        [
            gate("district-scheduling-me.json", SchedulingAdminSuccess<SchedulingMe>.self),
            gate("district-scheduling-branding.json", SchedulingAdminSuccess<SchedulingBranding>.self),
            gate("district-scheduling-llm.json", SchedulingAdminSuccess<SchedulingLLMSettings>.self),
            // ⚠️ NOT AN OP. The multipart route's answer, see the ⛔ on
            // ``schedulingC``. It is filed beside branding because `logo` and
            // `banner` are the two targets a branding screen sends.
            gate("district-scheduling-upload.json", SchedulingAdminSuccess<SchedulingUploadResult>.self),
        ]
    }

    /// `apiKeys.*`, `oauth.connections.*` and `webhooks.*`.
    ///
    /// ⚠️ THE THREE `items` LISTS ALL CARRY A SECOND ROW WHOSE NULLS ARE THE POINT,
    /// and they are not the same null. The unused API key nulls `last_used_at`; the
    /// OAuth connection nulls that AND `expires_at`, where nil means "does not
    /// expire" rather than "expired"; the inactive webhook nulls `fields`, where nil
    /// means "the fork's default set" rather than "no fields". Three fixtures, three
    /// different wrong readings, each one a claim a customer would act on.
    private static var developerFixtures: [ImplementedFixture] {
        [
            gate(
                "district-scheduling-api-keys.json",
                SchedulingAdminSuccess<SchedulingItems<SchedulingAPIKey>>.self
            ),
            gate("district-scheduling-api-key-created.json", SchedulingAdminSuccess<SchedulingAPIKeyCreated>.self),
            gate(
                "district-scheduling-oauth-connections.json",
                SchedulingAdminSuccess<SchedulingItems<SchedulingOAuthConnection>>.self
            ),
            gate(
                "district-scheduling-webhooks.json",
                SchedulingAdminSuccess<SchedulingItems<SchedulingWebhook>>.self
            ),
            gate("district-scheduling-webhook-created.json", SchedulingAdminSuccess<SchedulingWebhookCreated>.self),
            gate(
                "district-scheduling-webhook-deliveries.json",
                SchedulingAdminSuccess<SchedulingItems<SchedulingWebhookDelivery>>.self
            ),
        ]
    }
}
