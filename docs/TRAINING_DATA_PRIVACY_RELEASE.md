# Training backup and Coach history: release review

Updated 28 September 2026. Engineering handoff, not a legal compliance certification.

## Implemented controls

- Cloud backup, Coach training-history access and Coach health-data access are separate opt-ins, all default off and scoped to the authenticated account.
- Supabase records backup consent, version and last change time per authenticated account.
- Database trigger serializes every backup write with revocation/deletion. Old clients cannot write without consent. Deleting backups revokes consent for the account and deletes live rows in one transaction; a second device cannot silently recreate them.
- RLS confines backup and consent access to the owner. Account deletion cascades both tables.
- Backups include app-created plans, goals, libraries, Coach preferences, strength logs and phone workout summaries. Goals/free-text notes can still be health information. Planned routes include locations.
- The backup encoder removes imported strength health metrics, recorded phone GPS traces and the onboarding health/profile record. Corrupt histories fail closed instead of bypassing filtering.
- Photos and source Apple Health records are excluded. Restoring a filtered backup does not recover those exclusions. Existing local profile/consent choices are preserved during restore.
- Coach history permission gates both plan creation and plan adaptation. History summaries exclude raw pulse, sleep, HRV and GPS; plan/goals/notes intentionally supplied for the Coach request remain separate inputs.
- Coach health-data permission separately gates Recovery AI and workout AI insights. Without it, Recovery stays on deterministic on-device scoring and workout AI generation is skipped. The consent is account-scoped, removed on account deletion and is not included in cloud backup.
- Recovery AI caches are already account-scoped. Workout AI cache keys are now also account-scoped so generated health-derived insight cannot be reused across ATHLTH accounts on one device.
- Latest backup per device plus pre-restore copies are retained until backup/account deletion. This is not two-way sync. Provider disaster-recovery retention is separate.

## Verified configuration and evidence

Supabase project `hnkybbzxffvyhzrstqdo` reports database region `eu-north-1` (Stockholm). Region is not proof that support, logs, Edge Functions or subprocessors process exclusively in the EEA. There were zero backup rows when the consent gate was installed.

Run `supabase/tests/training_backup_consent.sql` in a controlled transaction; it rolls back and tests no-consent rejection, cross-account isolation, deletion and rejected recreation. Swift regression tests cover account isolation, checkpoint recovery, default-off consent, AI-health consent isolation/deletion, workout-launch preparation, filtering and malformed backups.

## Owner decisions/evidence required before public launch

1. Confirm the legal controller identity/privacy contact are configured in the app and publication materials.
2. Confirm applicable Supabase and Groq DPAs for the actual contracting entity/account. Do not assume the presence of a published template means the required agreement is in place.
3. Document lawful bases (including the additional condition for any health information), consent information and withdrawal records; assess DPIA requirements for health/location profiling and AI use.
4. Review each provider’s current subprocessors, support access, processing locations and international-transfer safeguards, including Groq inference. EU database hosting alone is insufficient.
5. Verify actual Supabase backup/PITR retention and Groq request-retention settings in the organization accounts; record exact periods and update published notices. Do not promise immediate destruction of provider recovery copies.
6. Complete access/export/deletion and breach-handling procedures, including an incident restore procedure that reapplies consent revocations/deletions before exposing a restored database.
7. Review App Store privacy disclosures and HealthKit requirements; validate on-device consent/offline/error flows before production rollout.

## Primary references checked

- https://supabase.com/docs/guides/security/gdpr-compliance
- https://supabase.com/legal/customer-resources/data-processing-addendum
- https://supabase.com/legal/customer-resources/subprocessor-list
- https://supabase.com/docs/guides/platform/backups
- https://console.groq.com/docs/legal/customer-data-processing-addendum
- https://console.groq.com/docs/your-data
- https://www.datatilsynet.no/rettigheter-og-plikter/virksomhetenes-plikter/om-behandlingsgrunnlag/spesielt-om-sarlige-kategorier-av-personopplysninger/
- https://www.datatilsynet.no/rettigheter-og-plikter/virksomhetenes-plikter/overforing-av-personopplysninger-ut-av-eos/
