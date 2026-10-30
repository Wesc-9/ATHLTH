# ATHLTH cross-device plan sync safety

Current status: Conflict-policy code and tests only. Not active in Android or iOS.

The existing iPhone account_training_backups is an optional backup and not a two-way sync protocol. The existing training_backup_consent must not be interpreted as permission to start continuous data synchronization.

The sync transport shall carry only user-authored plan and workout-template documents, not imported Apple Health or Health Connect sensor records, personal limitations, or precise routes. A separate, explicit opt-in for synchronization is required and should start disabled.

Every plan needs stable UUID identity, schema version, a monotonic server revision and source device. Conditional compare-and-swap writes must be enforced server-side. A stale update must surface a conflict rather than overwrite another device. Deletions need acknowledged tombstones and account deletion/revocation must remove all cloud copies. Offline edits require queueing and replay only after a new consent check.

The Android Kotlin TrainingSyncPolicy implements the decision rules for local versus remote documents. These are not proof of server enforcement. Next server step is a reviewed Supabase migration with RLS, revocation tests, conditional-write logic, and golden JSON fixtures from the current Swift models.

A separate reviewed iOS feature-branch adapter is required before Android/iPhone can truly synchronize the same plans. Do not merge to the iOS release or expose cloud-sync controls while these gates remain incomplete.
