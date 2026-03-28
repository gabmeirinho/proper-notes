# Technical Plan: Proper Notes v1

An implementation plan for a private, offline-first note-taking app targeting Linux desktop and Android.

## 0. Status Snapshot

Current project state as of March 2026:

Completed:
- local CRUD for notes
- deleted-notes flow and restore
- local search
- Linux sign-in flow
- Android sign-in flow
- manual sync between Linux and Android
- Drive delta sync with stored change tokens
- cross-device create, edit, delete, restore, and conflict-copy preservation
- release build validation on Linux and Android
- QA checklist for v1 release gating
- full manual QA checklist pass on Linux and Android release builds

Still remaining before calling v1 done:
- add more automated coverage for stale-device and restore scenarios
- decide the minimum release packaging/distribution process
- tighten a few UX rough edges around sync/account status
- tag and document the first release candidate

Primary handoff file for the next chat/agent:
- see `NEXT_STEPS.md`

Explicitly deferred until after the first usable v1:
- background sync
- Android WorkManager integration
- broader visual redesign
- advanced packaging/release automation

## 1. Product Goal

Build a note app that feels fast and reliable offline, stores all user data locally first, and syncs between devices without requiring a custom backend.

Primary goals:
- Linux desktop and Android from one codebase
- Local-first behavior
- Private per-user sync
- Simple markdown/plain text notes
- Robust enough to trust with real notes

Non-goals for v1:
- Real-time collaboration
- Rich block editor
- Shared notebooks
- End-to-end encryption
- Web app

## 2. Architecture

The app follows a local-first architecture:

- The UI reads and writes only to the local database.
- A sync engine runs separately from the editor and reconciles local state with remote state.
- Remote storage is treated as a transport and backup layer, not as the source of truth.

This keeps editing responsive and allows the app to work fully offline.

## 3. Technology Choices

- Language: Dart 3.x
- App framework: Flutter
- Local database: Drift over SQLite
- Remote storage: Google Drive API v3 using `appDataFolder`
- Authentication: system-browser OAuth on Linux and Google Sign-In on Android
- Android background jobs: WorkManager

### Why Drift

Drift is the preferred database layer for this app because:

- Sync state is relational by nature: notes, tombstones, sync state, and future revisions fit well in SQLite tables.
- SQLite is stable, inspectable, and easy to debug on desktop.
- Migrations are more predictable for long-lived user data.
- Search, filtering, ordering, and future features such as tags or note history are easier to extend cleanly.

Isar is still a viable option, but it is a worse default for a notes app that will likely accumulate sync metadata, migrations, and desktop debugging needs.

## 4. Cloud Strategy

Google Drive `appDataFolder` is the initial sync backend.

Why this is acceptable for v1:
- No custom server to operate
- Per-user private storage
- Hidden app storage avoids clutter in the user's Drive

Known tradeoffs:
- OAuth setup is more complex on Linux than on mobile
- Drive is a file store, not a sync database
- Conflict resolution and retry safety must be handled in the app

The backend should be abstracted behind a sync interface so Drive can be replaced later if needed.

## 4.1 Authentication Direction

The current split auth model remains the v1 direction:

- Linux uses system-browser OAuth with PKCE and a persisted refresh token.
- Android uses `google_sign_in` for account identity and Drive authorization.
- The account sheet reflects locally stored account metadata.
- Sync should reuse existing credentials silently when possible and should not start interactive auth unless the user explicitly chooses to sign in again.

This is an intentional product tradeoff for v1:

- it keeps the Android flow simpler than a full browser/deep-link OAuth implementation
- it matches the current working implementation
- it avoids introducing a large auth migration while sync correctness is still the higher-priority area

Known limitations:

- Android credential behavior is more dependent on Google Sign-In platform behavior than Linux
- Android and Linux do not share the exact same credential model
- if Google revokes or expires Android authorization state, the app may still need an explicit user reauthentication step

## 5. Data Model

Use the app's own UUID as the canonical note identity. Do not depend on the remote file id as the primary identity.

### Notes table

| Field | Type | Purpose |
| :--- | :--- | :--- |
| `id` | `TEXT` | Stable UUID created locally |
| `title` | `TEXT` | Optional user-facing title |
| `content` | `TEXT` | Markdown or plain text body |
| `created_at` | `INTEGER` | Creation timestamp |
| `updated_at` | `INTEGER` | Last local content update timestamp for UX and sorting, not primary sync correctness |
| `deleted_at` | `INTEGER?` | Soft-delete timestamp |
| `last_synced_at` | `INTEGER?` | Last successful sync timestamp |
| `sync_status` | `TEXT` | `synced`, `pending_upload`, `pending_delete`, `conflicted` |
| `content_hash` | `TEXT` | Used to avoid unnecessary uploads and improve conflict checks |
| `base_content_hash` | `TEXT?` | Hash of the note at the last successful sync baseline |
| `device_id` | `TEXT` | Device that last modified the note |
| `remote_file_id` | `TEXT?` | Drive file id, stored as a cache only |

### App metadata table

Stores:
- local `device_id`
- auth/account metadata
- `drive_sync_token`
- `last_full_sync_at`
- last successful sync time
- sync cursor or checkpoint data if later needed

### Optional future tables

- `note_revisions`
- `tags`
- `note_tags`

These are not required for v1 but the schema should not block them.

## 6. Remote File Format

Each remote note should be stored as one JSON file in Drive `appDataFolder`.

Suggested payload:

```json
{
  "id": "uuid",
  "title": "Example",
  "content": "note body",
  "created_at": 1710000000,
  "updated_at": 1710001234,
  "deleted_at": null,
  "device_id": "device-uuid",
  "content_hash": "sha256..."
}
```

Use the note UUID in the file name to simplify lookup and recovery.

Example:

```text
note_<uuid>.json
```

Deletion state should also be represented explicitly. For v1, the safest approach is to keep tombstone knowledge in app state and not rely on remote absence alone as proof of deletion.

## 7. Sync Model

Sync must be conservative. Losing note content is worse than creating duplicates.

### Core rules

- Local edits are written immediately to SQLite.
- Sync runs on app launch, manual sync, and selected background opportunities.
- Sync compares local records and remote records by note UUID.
- Deletions are soft-deleted first and only purged locally after successful remote reconciliation.
- Reconciliation should be based primarily on hashes and sync baseline state, not wall-clock timestamps.

### Conflict strategy

Do not use pure last-write-wins as the primary strategy.

Instead:
- If only one side changed since the last sync, accept that side.
- If both sides changed, create a conflict state.
- Preserve both versions instead of overwriting automatically.
- Mark the note as `conflicted` and surface it in the UI.

For v1, conflict resolution can be simple:
- keep local version as the active note
- store remote version as a duplicate note or revision copy
- append a suffix such as `(Conflict Copy)`

This is safer than silent overwrite and much easier to trust.

### Change detection

Do not use device wall-clock time as the primary signal for conflict detection. Device clocks drift and cannot be trusted for correctness.

Instead, compare:

- `base_content_hash`
- current local `content_hash`
- current remote `content_hash`

Interpretation:

- local == base and remote == base: unchanged
- local != base and remote == base: local changed
- local == base and remote != base: remote changed
- local != base and remote != base:
  - if local == remote, converge cleanly
  - otherwise create a conflict

`updated_at` remains useful for UI sorting, display, and debugging, but should not drive core reconciliation decisions.

### Drive delta sync

Do not rely on broad full scans of all note files on every sync cycle. For non-trivial note counts this creates an N+1 request pattern and will not scale well.

Use Google Drive change tracking:

- store `drive_sync_token` in app metadata
- bootstrap with a full sync only when required
- then use Drive change-list APIs to fetch only the delta since the last token
- download and reconcile only changed files

This should be the production sync model even if a full-scan path exists as a development fallback.

## 8. Sync Reconciliation Rules

For each note id:

1. Local only, not deleted:
   Upload remote file.

2. Remote only:
   Download and insert locally.

3. Exists on both sides, same hash:
   Mark synced, no action needed.

4. Local changed, remote unchanged:
   Upload local version.

5. Remote changed, local unchanged:
   Download remote version.

6. Both changed:
   Create conflict and preserve both copies.

7. Local pending delete, remote exists:
   Propagate deletion, keep tombstone state locally, then finalize cleanup only after retention policy allows it.

8. Remote deleted unexpectedly while local is unchanged:
   Treat absence cautiously. Re-upload local note unless the app has a recorded delete state or other explicit tombstone evidence.

## 9. Deletion Strategy

Hard-deleting note files remotely is not enough to represent deletion safely. Remote absence is ambiguous and can cause stale offline devices to resurrect deleted notes.

For v1:

- use local tombstones via `deleted_at`
- keep tombstones for a retention window such as 30 to 60 days
- do not purge tombstones immediately after remote reconciliation
- accept that very stale devices may still resurrect notes after the retention window if they were offline long enough

This is a deliberate tradeoff for v1. The stronger long-term model is explicit deletion propagation beyond simple remote absence.

## 10. Platform Notes

### Linux

- Store app data under the standard app data directory for Linux.
- Support keyboard shortcuts, context menus, and desktop-friendly list navigation.
- Start with foreground/manual sync only.
- Packaging is a late milestone, not an early dependency.
- Use system-browser OAuth as the main flow.
- Support loopback redirect handling.
- Provide a fallback manual auth-code entry flow if loopback capture fails.

### Android

- Store the database in internal app storage.
- Use WorkManager only after manual sync is proven reliable.
- Respect battery and network constraints for background sync.
- Use `google_sign_in` for account identity and Drive authorization.
- Reuse existing authorization silently during sync whenever possible.
- Do not require account chooser prompts during normal sync once credentials exist.

## 11. Implementation Strategy

Build the product in layers and do not start with sync complexity before the local app is trustworthy.

### Phase 1: Local app foundation

Status: Completed

- Flutter app shell
- Drift schema and migrations
- Note list and editor
- Create, update, delete, restore
- Search and ordering by recent update

### Phase 2: Authentication and account linking

Status: Completed for the current v1 auth model

- Google Cloud project setup
- Secure local credential storage for visible account metadata
- OAuth flow for Linux desktop via system browser
- Google Sign-In flow for Android
- Loopback redirect capture for Linux
- Manual fallback auth-code entry for Linux
- Session restore and sign-out
- Silent credential reuse for sync where platform APIs allow it

### Phase 3: Manual sync engine

Status: Completed as the current baseline, with further hardening still useful

- Remote file serialization
- Baseline-hash reconciliation logic
- Upload/download/delete operations
- Drive delta sync via change tokens
- Reconciliation logic
- Sync status in UI
- Retry handling and partial failure recovery

### Phase 4: Conflict and reliability hardening

Status: In progress

- Conflict copy flow
  Status: Completed for current create/edit/delete/restore conflict handling
- Tombstone cleanup
  Status: Not started
- Tombstone retention policy
  Status: Designed, not fully implemented as an automated cleanup flow
- Crash-safe sync transitions
  Status: Partially addressed, still worth more testing
- Schema migration testing
  Status: Not started
- Multi-device sync testing
  Status: Completed for the current release-candidate pass, worth repeating only when new sync logic changes land
- Automated regression coverage for restore and stale-device cases
  Status: In progress
- Final v1 bug bash against `QA_CHECKLIST.md`
  Status: Completed on current Linux and Android release builds

### Phase 5: Background sync and packaging

Status: Partially deferred

- Android WorkManager integration
  Status: Deferred until after first stable v1
- Sync throttling rules
  Status: Deferred with background sync work
- Linux packaging
  Status: Basic launcher/install flow exists
- Release pipeline
  Status: Manual build/install flow exists, automation not started

### Phase 6: First v1 release candidate

Status: In progress

- Rebuild Linux and Android release builds from the latest code
- Run the full `QA_CHECKLIST.md`
  Status: Completed
- Fix any remaining reproducible data-loss or restore/sync regressions
  Status: Completed for the current release-candidate pass
- Freeze architecture changes
- Tag a first release candidate build
- Write short release notes
- Record the tested build/version against the QA pass

## 12. Quality Requirements

Before considering v1 usable, the app should satisfy these conditions:

- Notes are editable offline with no degraded UX
- App restart does not lose unsynced changes
- Sync retries are idempotent
- A failed sync cannot corrupt the local database
- Conflict cases preserve data instead of overwriting it
- Database migrations are tested
- Clock skew between devices does not cause incorrect overwrite behavior
- Large note collections do not require full remote scans on every sync

## 13. Testing Strategy

Minimum required test coverage:

- unit tests for note repository logic
- unit tests for sync reconciliation rules
- serialization tests for remote payloads
- migration tests for Drift schema changes
- integration tests for:
  - offline edit then sync
  - delete and restore flows
  - two-device conflict scenarios
  - clock-skew scenarios across devices
  - stale-device resurrection scenarios
  - Drive delta-sync token recovery
  - auth recovery after app restart
  - Android cold-start sync without interactive re-login
  - Android release-build auth behavior

Current status:
- repository tests exist
- sync reconciliation tests exist
- auth/session storage tests exist
- gateway-level regression tests exist
- migration tests are still missing
- broader integration coverage is still mostly manual via the QA checklist, and the latest full manual pass succeeded on release builds

## 14. Future Extensions

Possible post-v1 features:
- tags and notebooks
- pinned notes
- note history
- attachments
- optional end-to-end encryption
- pluggable sync backends

## 15. Final Recommendation

For v1, the most defensible path is:

- Flutter for cross-platform UI
- Drift + SQLite for local persistence
- Google Drive `appDataFolder` as a temporary sync backend
- manual sync first
- conflict-safe behavior instead of aggressive overwrite logic

The app should earn trust through reliability first. Background automation and packaging should come after the local data model and sync engine are proven stable.
