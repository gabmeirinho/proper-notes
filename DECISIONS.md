# DECISIONS.md

This file records architectural decisions for Proper Notes.

Format:
- `Status`: current state of the decision
- `Decision`: what was chosen
- `Why`: primary reasoning
- `Consequences`: tradeoffs and follow-up implications

## D-001: Local-First Architecture

- Status: Accepted
- Decision: The app uses a local-first architecture where the local database is the source of truth and sync is a separate reconciliation process.
- Why:
  - notes must remain usable offline
  - editing must not depend on network latency or backend availability
  - local persistence is easier to trust and recover from than remote-first behavior
- Consequences:
  - sync must be designed as a background or manual reconciliation layer
  - the UI should only read and write local state
  - remote inconsistencies must never directly corrupt local note editing flows

## D-002: Flutter For Linux And Android

- Status: Accepted
- Decision: Build the app with Flutter and Dart for Linux desktop and Android.
- Why:
  - one codebase for the first two target platforms
  - strong UI iteration speed
  - reasonable desktop and mobile support for the scope of v1
- Consequences:
  - some platform-specific work remains, especially auth and background sync
  - desktop UX needs explicit care and should not be treated like stretched mobile UI

## D-003: Drift Over Isar

- Status: Accepted
- Decision: Use Drift over SQLite as the primary local persistence layer for v1.
- Why:
  - sync metadata is relational and fits SQLite naturally
  - schema evolution and migrations are clearer and more predictable
  - SQLite is easy to inspect and debug on Linux
  - search, sorting, tags, revisions, and future filtering are easier to extend cleanly
- Consequences:
  - schema design and migrations must be handled explicitly
  - agents should not introduce alternative storage models casually

## D-004: Google Drive `appDataFolder` As Initial Sync Backend

- Status: Accepted
- Decision: Use Google Drive `appDataFolder` as the first sync backend instead of operating a custom server.
- Why:
  - avoids backend infrastructure for v1
  - gives per-user private storage
  - hidden storage reduces user-facing Drive clutter
- Consequences:
  - Drive must be abstracted behind a sync interface
  - OAuth on Linux is a real implementation concern
  - Drive is a file store, so conflict handling and sync safety remain application responsibilities
  - this backend may be replaced later if product scope expands

## D-005: App-Owned UUIDs As Canonical Note Identity

- Status: Accepted
- Decision: Each note uses an app-generated UUID as canonical identity.
- Why:
  - identity must remain stable across devices and sync retries
  - file paths and Drive file ids are not suitable as the primary identifier
- Consequences:
  - remote file ids are metadata only
  - rename, move, and storage changes should not affect note identity

## D-006: Markdown As Content Format, Not Storage Architecture

- Status: Accepted
- Decision: Note bodies may use markdown text, but the canonical storage model for v1 is the local database rather than a folder of `.md` files.
- Why:
  - sync state requires structured metadata beyond note body text
  - deletions, conflicts, and migrations are easier to handle in a database
  - Android and Linux storage behavior is simpler with an app-managed persistence layer
- Consequences:
  - markdown export/import can be added later
  - the product is not committing to an Obsidian-style vault model in v1

## D-007: Conflict Preservation Over Last-Write-Wins

- Status: Accepted
- Decision: Do not use pure last-write-wins as the main conflict strategy.
- Why:
  - silent overwrites are unacceptable for note-taking software
  - concurrent edits across devices are normal and must not destroy content
- Consequences:
  - conflicts should preserve both versions
  - the UI must surface conflict state
  - duplicate or revision-copy behavior is preferable to lost text

## D-008: Hash-Based Reconciliation Over Timestamp-Driven Correctness

- Status: Accepted
- Decision: Core sync reconciliation should be based on hashes and sync baseline state, not primarily on wall-clock timestamp comparisons.
- Why:
  - device clocks drift
  - clock skew can cause incorrect overwrite decisions
  - a baseline hash model is more reliable for detecting local-only, remote-only, and concurrent changes
- Consequences:
  - `updated_at` remains useful for UX and diagnostics, but not for correctness
  - note records require `content_hash` and `base_content_hash`

## D-009: Drive Delta Sync With Change Tokens

- Status: Accepted
- Decision: Production sync should use Google Drive change tracking instead of repeated full scans of all note files.
- Why:
  - one-file-per-note storage does not scale well with naive polling
  - repeated broad scans create unnecessary API calls and rate-limit risk
  - delta sync is more efficient and better aligned with large note collections
- Consequences:
  - app metadata must store `drive_sync_token`
  - the sync engine needs a bootstrap path for first sync and token recovery
  - a full-scan path may still exist for development or recovery, but should not be the normal path

## D-010: Tombstones For Deletions

- Status: Accepted
- Decision: Deletions use tombstone semantics before any final purge.
- Why:
  - immediate hard deletes are unsafe in multi-device sync
  - stale offline devices can otherwise recreate deleted notes
- Consequences:
  - notes need `deleted_at` and deletion-related sync state
  - missing remote files must not automatically be treated as proof of deletion
  - tombstones require a cleanup policy

## D-011: Tombstone Retention Window For v1

- Status: Accepted
- Decision: Keep local tombstones for a retention period such as 30 to 60 days before final purge.
- Why:
  - this reduces zombie-note resurrection from stale devices
  - it prevents tombstones from accumulating forever
- Consequences:
  - very stale devices may still resurrect old notes after the retention window
  - this is a pragmatic v1 tradeoff, not a perfect long-term deletion model

## D-012: Manual Sync Before Background Sync

- Status: Accepted
- Decision: Build and prove manual sync first, then add background sync later.
- Why:
  - sync correctness is easier to validate in a foreground/manual flow
  - background sync adds platform complexity and obscures failures
- Consequences:
  - WorkManager and desktop background behavior are phase-later concerns
  - early product quality depends more on sync correctness than automation

## D-013: Linux OAuth Requires Fallback

- Status: Accepted
- Decision: Linux authentication should use the system browser with loopback redirect handling and a manual fallback path when loopback capture fails.
- Why:
  - desktop OAuth flows are more brittle than mobile flows
  - ports, environment differences, and system configuration can break the happy path
- Consequences:
  - auth flow must not assume loopback success
  - auth UX needs a fallback that still allows account linking

## D-014: Keep The Current Split Auth Model For v1

- Status: Accepted
- Decision: Keep Linux on browser OAuth with PKCE and keep Android on `google_sign_in` for v1 instead of migrating Android to browser-based OAuth.
- Why:
  - the current implementation is working and matches the immediate product needs
  - a full Android auth migration would add substantial complexity without improving the core sync model enough to justify the disruption right now
  - the project should prioritize sync correctness, conflict safety, and day-to-day reliability over auth unification
- Consequences:
  - Linux and Android use different credential models in v1
  - Android auth behavior remains somewhat constrained by the Google Sign-In plugin and platform behavior
  - future auth work should improve credential reuse and UX within the current model, not assume a planned migration away from it
