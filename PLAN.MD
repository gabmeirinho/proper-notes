# Technical Plan: Shift Proper Notes From Google OAuth/Drive To WebDAV/Nextcloud

This file replaces the previous editor-focused plan.

It defines the target architecture and delivery plan for moving Proper Notes from:
- Google OAuth for account linking
- Google Drive `appDataFolder` as the sync transport

to:
- direct WebDAV credentials
- Nextcloud as the initial supported WebDAV server
- a sync design that remains local-first and conflict-safe without Google-specific APIs

## 1. Executive Summary

Proper Notes should keep its current local-first foundations and current note model, but replace the remote backend and authentication model.

What should stay:
- Flutter app
- Dart 3.x
- Drift over SQLite
- local database as the source of truth
- manual sync as the baseline
- app-owned UUID note identity
- conservative conflict preservation
- tombstone-first deletion handling

What should change:
- remove Google OAuth from the product surface
- remove Google Drive as the sync backend
- replace token/session logic with WebDAV credential storage
- replace Drive delta-token sync with WebDAV listing and ETag-based reconciliation
- introduce a remote folder layout that is independent of provider-specific ids

Recommended v1 target:
- support one configured WebDAV account at a time
- explicitly target Nextcloud first
- use a plain WebDAV endpoint, username, and app password
- keep the backend abstraction clean enough that generic WebDAV servers remain possible later

## 2. Product Goals

The backend shift should deliver:
- offline-first editing with no network dependency for core note work
- manual sync to a Nextcloud server through WebDAV
- a setup flow that works on Linux and Android without browser-based OAuth
- safe remote note create, update, delete, and restore behavior
- attachment sync that keeps pasted image behavior working
- a migration path for users coming from existing Google-backed builds

The backend shift must not weaken:
- local DB authority
- debuggability
- conflict preservation
- stale-device recovery
- deletion safety

## 3. Explicit Non-Goals For This Shift

This migration should not turn into a larger product rewrite.

Out of scope unless explicitly requested:
- reintroducing browser-based auth for Nextcloud OAuth2
- supporting multiple sync backends in the product UI
- building a server-side companion service
- changing note identity to remote paths or hrefs
- redesigning the editor into a block editor
- end-to-end encryption
- always-on background sync as a prerequisite for launch

## 4. Current Starting Point In The Codebase

The current app already has useful boundaries that should be preserved:
- `lib/features/auth/domain/auth_service.dart`
- `lib/features/sync/domain/sync_gateway.dart`
- `lib/features/sync/domain/sync_state_repository.dart`
- `lib/infrastructure/auth/*`
- `lib/infrastructure/sync/google_drive_sync_gateway.dart`
- `lib/infrastructure/repositories/drift_sync_state_repository.dart`
- `lib/infrastructure/database/app_database.dart`

Important current facts:
- the app is already local-first
- sync is already behind `SyncGateway`
- account/session behavior is already behind `AuthService`
- app metadata currently stores `driveSyncToken`
- remote note identity is already app-owned `id`, while `remoteFileId` is only cache metadata

This means the migration can be done as a backend replacement rather than an architectural reset.

## 5. Target Product Direction

### 5.1 User-Facing Account Model

The Google account model should be replaced with a sync account model based on:
- server base URL
- WebDAV root path
- username
- app password
- optional display label derived from server host plus username

Recommended UX:
- one `Sync account` sheet instead of a Google sign-in sheet
- fields for server URL, username, password, and optional folder override
- a `Test connection` action before saving
- an explicit `Disconnect` action that clears secrets but does not delete local notes

For Nextcloud specifically:
- recommend app passwords rather than the main account password
- default the remote root to a dedicated folder under the user WebDAV space
- make the default path deterministic and human-readable

### 5.2 Recommended Remote Root

Recommended default root for Nextcloud:
- `.../remote.php/dav/files/<username>/ProperNotes/`

The app should also allow an explicitly supplied WebDAV collection URL so advanced users can point at:
- a subfolder in Nextcloud
- another compatible WebDAV server

The UI should describe Nextcloud as the supported primary target, but the core sync layer should remain WebDAV-oriented rather than hard-coded to a vendor SDK.

## 6. Remote Storage Design

### 6.1 Why Drive-Like Sync No Longer Applies

Google Drive `appDataFolder` gave the app:
- provider-owned hidden storage
- file ids
- change tokens
- OAuth-backed account identity

WebDAV does not guarantee those features.

The new design must assume:
- no provider change token
- no app-private hidden space
- no canonical remote file id
- no guaranteed stable timestamp semantics across servers
- no first-class account identity beyond supplied credentials

### 6.2 Remote Folder Layout

Use a deterministic, app-owned folder structure:

```text
ProperNotes/
  meta/
    schema.json
  notes/
    <note-id>.json
  tombstones/
    <note-id>.json
  attachments/
    <attachment-name-or-hash>
```

Recommended responsibilities:
- `meta/schema.json`: remote format version and basic installation metadata
- `notes/<id>.json`: full note snapshot for active or restorable notes
- `tombstones/<id>.json`: deletion record written before any purge
- `attachments/*`: binary attachments referenced by note content

### 6.3 Remote Note Shape

The remote note payload should stay close to the local note model so debugging remains simple.

Suggested shape:

```json
{
  "id": "uuid",
  "title": "Example",
  "content": "note body",
  "document_json": "{...}",
  "created_at": 1710000000000,
  "updated_at": 1710001000000,
  "deleted_at": null,
  "content_hash": "sha256:...",
  "base_content_hash": "sha256:...",
  "device_id": "device-1",
  "folder_path": "Work/Inbox",
  "schema_version": 1
}
```

Notes:
- `document_json` should be included because the local schema already has it
- `content` remains for compatibility and debugging while the text-note model remains primary
- `updated_at` is useful UX metadata, not correctness authority
- `content_hash` and `base_content_hash` remain central to reconciliation

### 6.4 Tombstone Shape

Suggested tombstone payload:

```json
{
  "id": "uuid",
  "deleted_at": 1710002000000,
  "last_content_hash": "sha256:...",
  "device_id": "device-1",
  "schema_version": 1
}
```

Rules:
- write a tombstone before treating a note as remotely deleted
- do not treat absence of `notes/<id>.json` as sufficient evidence of deletion
- a missing note file with no tombstone is ambiguous and must not immediately delete local content

## 7. Local Data And Schema Changes

### 7.1 Notes Table

The existing `notes` table can largely survive this migration.

Important fields that should remain:
- `id`
- `title`
- `content`
- `document_json`
- `created_at`
- `updated_at`
- `deleted_at`
- `last_synced_at`
- `sync_status`
- `content_hash`
- `base_content_hash`
- `device_id`
- `folder_path`
- `remote_file_id`

`remote_file_id` should not be treated as a Drive-only concept anymore.

Recommended interpretation after the shift:
- store the remote note path or href cache there temporarily if useful
- or replace it with a more generic field in a reviewed migration

Do not let the name force the design. It remains cache metadata only.

### 7.2 App Metadata Table

The current metadata table includes:
- `device_id`
- `account_email`
- `drive_sync_token`
- `last_full_sync_at`
- `last_successful_sync_at`

This needs a reviewed migration.

Recommended replacement direction:
- `device_id`
- `account_label`
- `remote_base_url`
- `remote_username`
- `remote_collection_tag` or nullable generic sync marker
- `last_full_sync_at`
- `last_successful_sync_at`
- optional `remote_format_version`

Important rule:
- do not store raw passwords in SQLite
- store secrets in secure storage only

### 7.3 Credential Storage

Replace the OAuth session store with a credential store.

Recommended stored secrets:
- password or app password
- possibly cached auth header material if needed

Recommended non-secret preferences:
- server URL
- username
- display label
- optional custom root path

The storage split should stay explicit so secrets do not leak into logs, backups, or plain preferences by accident.

## 8. Code Architecture Changes

### 8.1 Authentication Layer

The existing `AuthService` boundary should be reviewed.

Recommended direction:
- either keep `AuthService` but reinterpret it as sync-account connection management
- or rename it to something like `SyncAccountService` or `RemoteCredentialService`

Either way, the old semantics of:
- `restoreSession()`
- `signIn()`
- `signOut()`

should evolve into something like:
- restore saved account config
- save/test credentials
- clear credentials

The important goal is not naming purity. The goal is that UI code still does not own network auth details.

### 8.2 Sync Gateway

`SyncGateway` should remain the main remote boundary, but the implementation changes materially.

The new gateway should:
- create required remote folders if missing
- fetch remote listings via `PROPFIND`
- retrieve changed note files with `GET`
- upload note payloads with `PUT`
- upload attachments with `PUT`
- create tombstones with `PUT`
- use `DELETE` sparingly and only when a reviewed purge policy exists

The current Google implementation should be replaced by a new WebDAV implementation rather than mixed together behind flags.

Recommended file direction:
- add `lib/infrastructure/sync/webdav_sync_gateway.dart`
- later remove `google_drive_sync_gateway.dart`

### 8.3 Sync State Repository

The current repository is Drive-specific because it exposes:
- `getDriveSyncToken()`
- `setDriveSyncToken()`

This should be generalized.

Recommended replacement:
- `getRemoteSyncCursor()`
- `setRemoteSyncCursor()`
- or `getRemoteCollectionTag()` if the stored value is explicitly a collection fingerprint

Important rule:
- any stored cursor is an optimization hint, not the sole correctness mechanism

### 8.4 App Bootstrap

`lib/app/proper_notes_app.dart` currently wires Google config, Google auth services, and the Drive sync gateway.

The bootstrap rewrite should:
- remove Google-specific environment handling
- inject the new credential/config store
- inject the WebDAV sync gateway
- keep `SyncController`, `RunManualSync`, and note repositories intact where possible

This is one of the main files where the backend cutover will become visible.

## 9. Sync Algorithm For WebDAV

### 9.1 Baseline Strategy

Because generic WebDAV does not provide a Drive-like delta stream, the correctness baseline should be:
- list remote directories
- compare local metadata against remote file existence plus ETag
- fetch changed payloads
- reconcile locally using hashes and deletion state

This is less elegant than Drive change tokens, but it is portable and understandable.

### 9.2 Listing Strategy

For each sync run:
- `PROPFIND` the `notes/` directory with `Depth: 1`
- `PROPFIND` the `tombstones/` directory with `Depth: 1`
- collect `href`, `getetag`, `getcontentlength`, and `getlastmodified` if available

If Nextcloud exposes collection tags or other server metadata:
- use them as a short-circuit optimization
- never use them as the only correctness path

Recommended posture:
- if the server fingerprint is unchanged, optionally skip downloading unchanged files
- if server metadata is missing or suspicious, fall back to explicit listing and content fetch

### 9.3 Fetch Strategy

Use `GET` for note or tombstone payloads when:
- the file is newly discovered
- the ETag changed
- local cache metadata is missing
- a previous sync ended mid-run
- server metadata looks inconsistent

Avoid making correctness depend on `Last-Modified`.

### 9.4 Upload Strategy

For note writes:
- serialize the full note snapshot
- `PUT` to `notes/<id>.json`
- optionally use conditional headers when supported, but do not rely on them universally

For deletions:
- write `tombstones/<id>.json`
- keep local deletion as a tombstone state
- do not immediately hard-delete remote note files unless the purge flow is explicit and reviewed

For restores:
- restore the note payload
- clear or supersede the tombstone in a controlled way

### 9.5 Attachments

The current app already has attachment utilities and attachment-aware sync behavior.

Recommended remote strategy:
- name attachment files by a stable derived name, ideally hash-based
- upload only when the remote file is missing or the content hash differs
- do not infer note deletion from attachment absence alone
- keep attachment sync separate from note payload sync so retries remain idempotent

## 10. Conflict And Deletion Rules Under WebDAV

### 10.1 Conflict Detection

The minimum conflict model stays the same:
- detect local-only changes
- detect remote-only changes
- detect concurrent changes
- preserve both versions when safe auto-resolution is not available

Correctness inputs should continue to be:
- `content_hash`
- `base_content_hash`
- explicit deletion state
- known sync lineage

Not primary correctness inputs:
- remote timestamps
- client clock ordering
- server clock ordering

### 10.2 Ambiguous Missing Remote Files

With WebDAV, absence is even more ambiguous than in Drive.

Possible reasons a note file is missing:
- another client deleted it intentionally
- the folder is partially synced
- credentials point at the wrong root
- the server had a transient listing failure
- the note never uploaded successfully

Required behavior:
- never hard-delete local content because a remote file is missing by itself
- require a tombstone or other strong evidence before applying remote deletion
- surface sync issues when the remote collection looks incomplete

### 10.3 Stale Devices

The design must continue to support devices returning after long offline periods.

Rules:
- stale devices must re-list the remote state rather than trust an old cursor blindly
- stale uploads must still reconcile against current tombstones and content hashes
- if a stale device conflicts with newer remote changes, preserve both versions

## 11. Migration Plan From Existing Google Builds

### 11.1 Product-Level Migration

Users upgrading from a Google-backed build should experience:
- local notes remain untouched
- existing local sync metadata remains readable during transition
- Google credentials are eventually cleared after the new backend is stable
- the app asks the user to configure WebDAV before sync resumes

There should be no attempt to perform an in-app Google-to-WebDAV remote copy unless explicitly designed and tested. That would add risk and a large amount of product surface.

Recommended posture:
- migrate local app state
- require a fresh remote bootstrap to WebDAV
- upload local authoritative notes to the new WebDAV target after explicit user action

### 11.2 Code-Level Migration Phases

#### Phase 1: Documentation And Interface Preparation

- rewrite `PLAN.MD`
- rewrite `AGENTS.md`
- rename Drive-specific concepts in interfaces where low-risk
- update tests that encode Drive-only vocabulary

#### Phase 2: Storage Migration

- add a reviewed Drift migration for new metadata fields
- deprecate or rename `drive_sync_token`
- add a new credential/config store
- preserve `device_id`

#### Phase 3: Credential UX

- replace Google sign-in UI with WebDAV connection UI
- add connection validation
- add disconnect flow
- show a human-readable connected account label

#### Phase 4: WebDAV Gateway Implementation

- implement remote folder bootstrap
- implement listing, fetch, upload, tombstone write, and attachment sync
- support authenticated requests on Linux and Android

#### Phase 5: Reconciliation Integration

- plug the new gateway into `RunManualSync` and `SyncController`
- replace Drive-token logic with generic remote sync state
- verify delete, restore, and conflict-copy preservation behavior

#### Phase 6: Cutover

- remove Google-specific bootstrap wiring
- remove unused OAuth code
- remove unused Google dependencies
- update user-facing docs and build instructions

#### Phase 7: Release Hardening

- run full test suite
- add migration coverage
- verify real-device Nextcloud interoperability
- verify upgrade from a Google-era local database

## 12. Testing Plan

This shift needs more than happy-path unit tests.

Required coverage areas:
- metadata migration tests
- credential store tests
- WebDAV XML parsing tests
- WebDAV gateway request/response tests
- sync reconciliation tests with WebDAV-specific failure modes
- attachment sync tests
- stale-device tests
- delete-resurrection tests
- conflict-copy preservation tests

Important WebDAV-specific cases:
- invalid credentials
- 401 and 403 handling
- 404 on missing remote folders during bootstrap
- malformed `PROPFIND` XML
- missing ETag values
- ETag changes without content change
- partial network failure mid-sync
- ambiguous note-file absence without tombstone
- duplicate remote files or unexpected extra files

Integration expectation:
- mock-based tests are required
- at least one repeatable manual verification checklist against a real Nextcloud server is also required

## 13. Dependency And Package Guidance

Do not add large vendor-specific SDKs unless the payoff is clear.

Preferred direction:
- keep using `http`
- add a small XML parser only if needed for `PROPFIND`
- use secure storage for secrets
- avoid locking the app to a Nextcloud-only client library if plain WebDAV is sufficient

Nextcloud-specific headers or behaviors may be used as optimizations, but they should not become the only supported protocol path unless the product deliberately gives up on broader WebDAV compatibility.

## 14. Release Gates

The backend shift should not be considered complete until:
- Google OAuth is gone from the normal product flow
- Google Drive is no longer required to build or run the app
- a new local install can connect to Nextcloud and sync notes safely
- an upgraded install preserves existing local notes and device identity
- conflict and deletion safety tests pass
- attachment sync works on both Linux and Android

## 15. Final Direction

Proper Notes should move to WebDAV/Nextcloud in a way that is intentionally boring:
- local data stays authoritative
- remote storage stays inspectable
- sync remains conservative
- credentials stay explicit
- conflict preservation stays more important than clever merge behavior

This migration is successful if the app becomes easier to self-host and easier to trust without weakening the data-safety rules that matter more than backend convenience.
