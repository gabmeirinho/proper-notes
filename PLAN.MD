# Proper Notes Backend Plan

This file is the reviewed source for the current backend and sync direction.
Keep implementation changes aligned with it, or update this file in the same
change when the direction intentionally changes.

## Current State

Proper Notes is now centered on the v1 backend direction:

- Flutter and Dart app for Linux and Android
- Drift over SQLite as the local source of truth
- WebDAV as the sync transport
- Nextcloud-compatible account setup through server URL, username, and app
  password
- manual sync as the correctness baseline
- tombstone-based deletes
- content-hash and base-content-hash reconciliation
- conflict copies when concurrent changes cannot be resolved safely
- attachment sync for note-referenced local images
- conflict and pending-sync status shown distinctly in the notes list and
  editor
- manual sync results shown after successful foreground sync without implying
  automatic conflict resolution
- clean `flutter analyze` output

Google Drive is not an active v1 backend. Legacy Google-era database fields may
remain only to preserve upgrade safety for existing local databases.

## Current Priority

The next milestone is v0.1 stabilization:

1. Keep the local database as the source of truth.
2. Keep sync conservative and conflict-safe.
3. Make the project clean under analyzer.
4. Keep docs aligned with the implementation.
5. Avoid adding new product surface until the existing backend path is boring
   and reliable.

Do not add a WebDAV smoke-test harness as part of this milestone. WebDAV
behavior should continue to be covered through focused unit and application
tests unless that priority is explicitly reopened later.

## Backend Rules

The backend must continue to follow these constraints:

- UI code must not call WebDAV directly.
- Remote sync logic must stay behind `SyncGateway`.
- Credential handling must stay behind the auth/account store boundary.
- WebDAV passwords must not be stored in SQLite.
- Note identity must use app-owned UUIDs.
- Remote paths, hrefs, ETags, and collection tags are cache metadata only.
- Sync correctness must not depend primarily on wall-clock timestamps.
- Missing remote files must not be treated as deletions by themselves.
- Deletes must remain tombstone-first.
- Conflict preservation is preferred over automatic merge behavior.

## Completed Backend Work

The current codebase already includes:

- Drift schema and migrations through schema version 6
- canonical `remote_sync_cursor` metadata
- legacy Drive-token migration coverage
- WebDAV deterministic remote layout
- note and tombstone upload/download behavior
- ETag-based fetch optimization with fallback when ETags are missing
- attachment upload and download behavior
- conflict-copy preservation
- stale-device, delete/edit, restore, retry, attachment retry, and
  shared-remote sync regression tests
- sync-result and conflict-status UI coverage

## Next Implementation Steps

### 1. Preserve Migration Safety

Any schema change must include:

- explicit Drift migration logic
- migration tests from older known schemas
- preservation of `device_id`
- preservation or deliberate migration of sync metadata
- no storage of WebDAV secrets in SQLite

Legacy Google-era fields should be removed only when there is a reviewed
migration plan proving old local databases upgrade safely.

### 2. Keep Sync Regression Coverage Current

Sync coverage is current for the existing backend behavior. When sync behavior
changes, add or update tests for the exact safety property.

Covered priority cases include:

- stale devices returning after remote changes
- local edit versus remote delete
- local delete versus remote edit
- tombstone and restore cycles
- partial sync failure followed by retry
- malformed WebDAV responses
- missing or unstable ETags
- attachment retry behavior

### 3. Finish Conflict UX Release Polish

Conflict and sync-status basics are now in place:

- conflict copies are called out in app-level sync status
- note/editor badges distinguish pending upload, pending delete, and conflict
- successful manual sync results are visible and dismissible
- conflict counts are described as preserved conflicts, not resolved conflicts

Remaining release-polish work should stay narrow:

- make the conflict resolution sheet clearer about which note is original and
  which note is the preserved conflict copy
- show enough note metadata in conflict resolution to compare versions without
  opening both notes first
- keep the resolution flow explicit: deleting or keeping a version must remain a
  user action
- add focused widget coverage for the conflict resolution choices

## Out Of Scope For This Milestone

- WebDAV smoke-test harness
- Google Drive or Google OAuth product support
- additional sync providers
- collaboration
- shared notebooks
- rich block editor expansion
- end-to-end encryption
- web app
- background sync as a correctness dependency

## Next Step

The next implementation step is to improve the conflict resolution sheet. It
should display both candidate versions with title, folder, updated time, and a
short content preview, then keep the existing explicit actions for opening or
choosing a version. This is product-facing polish only; it should not change
sync reconciliation, schema, or conflict-copy preservation semantics.

## Definition Of Done

This milestone is complete when:

- `flutter analyze` is clean
- `flutter test` is clean
- docs describe WebDAV as the current backend, not a migration placeholder
- `PLAN.MD` matches the implemented direction
- sync safety tests cover any behavior changed during the milestone
- no new feature work has weakened local-first or conflict-preserving behavior
