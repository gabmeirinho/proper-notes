# AGENTS.md

This file defines the working rules for coding agents contributing to Proper Notes.

## 1. Project Summary

Proper Notes is a local-first note-taking app for Linux desktop and Android.

Current v1 direction:
- Flutter app
- Dart 3.x
- Drift over SQLite for local persistence
- WebDAV as the sync protocol
- Nextcloud as the initial supported WebDAV target
- manual sync first, background sync later
- logical folders in local app state
- a single text-note model with `content` plus `document_json`

Core product goal:
- build a note app that is trustworthy offline
- preserve user data above all else
- sync across devices without requiring a custom backend

## 2. Product Principles

These principles are not optional:

- Local database is the source of truth.
- The UI must work without network access.
- Sync must never silently destroy user content.
- Conflict preservation is more important than aggressive auto-merge behavior.
- Simplicity is preferred unless it weakens data safety.
- Self-hostability is valuable, but not at the cost of reliability.

## 3. v1 Scope

In scope:
- plain text or markdown note content
- note create, edit, delete, restore
- nested folders with move and rename flows
- local search and ordering
- WebDAV account configuration
- Nextcloud connection support through WebDAV
- manual sync
- conflict-safe sync behavior
- attachment sync for note-referenced images

Out of scope for v1 unless explicitly requested:
- Google OAuth or Google Drive support in the product surface
- browser-based OAuth for Nextcloud
- collaboration
- shared notebooks
- rich block editor
- end-to-end encryption
- web app
- multi-backend sync support in the product surface

## 4. Architecture Rules

Agents must preserve these constraints:

- UI code must not talk directly to WebDAV or Nextcloud APIs.
- Remote sync logic must sit behind a sync interface.
- Credential handling must sit behind a dedicated service or store boundary.
- Note identity must use app-owned UUIDs, not remote paths, hrefs, or server ids.
- Remote hrefs, ETags, and collection tags are cache metadata only, never canonical identity.
- Reconciliation must not depend primarily on wall-clock timestamps.
- `updated_at` is for UX, sorting, and debugging, not correctness.
- Sync decisions should be based on state such as `content_hash`, `base_content_hash`, sync metadata, and explicit deletion state.
- Deletions must use tombstone semantics before any final purge.
- Missing remote files must be treated cautiously because absence is ambiguous.
- Remote folder layout must stay app-owned and deterministic.
- `PLAN.MD` is the reviewed source for the backend migration direction. Do not drift from it silently.

## 5. Data Safety Rules

If a change risks data loss, stop and redesign it.

Required safety behavior:
- never overwrite conflicting edits without preserving both versions
- never hard-delete local notes immediately after a remote delete action
- never infer deletion from a missing remote file alone
- never assume a device clock is correct
- never assume a server clock is correct
- never treat sync retries as one-shot operations
- never introduce schema changes without a migration plan

When uncertain, prefer:
- duplicate note over lost note
- conflict flag over silent merge
- explicit sync state over inferred state
- slower but understandable sync over clever but fragile behavior

## 6. Database Rules

Database choices should optimize long-term reliability and debuggability.

Rules:
- Drift is the default persistence layer for v1
- SQLite schema changes must be explicit
- migrations must be reviewed carefully
- migration tests are required for non-trivial schema changes
- avoid storing critical state only in memory if it is needed for sync recovery
- do not store WebDAV passwords in SQLite

Expected note metadata includes:
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
- remote cache metadata such as path or href if needed

App-level sync metadata should preserve:
- `device_id`
- last successful sync information
- remote account labeling or connection metadata
- a generic remote sync cursor only as an optimization hint

## 7. Sync Rules

The sync engine is a safety-critical subsystem.

Agents must follow these rules:
- use manual/foreground sync as the baseline before background sync work
- keep sync logic separate from UI widgets
- treat WebDAV as transport/storage, not source of truth
- prefer deterministic remote folder layout over provider-specific hidden storage
- use `PROPFIND` plus explicit file fetches as the correctness baseline
- treat ETags, collection tags, and similar server metadata as hints, not sole correctness inputs
- preserve enough metadata locally to recover from partial sync failures
- ensure sync operations are idempotent where possible
- design for stale devices returning after long offline periods
- keep attachment sync separate enough that retries are safe

Minimum conflict posture:
- detect local-only changes
- detect remote-only changes
- detect concurrent changes
- preserve both versions when concurrent changes cannot be resolved safely

## 8. WebDAV And Nextcloud Rules

Agents should assume Nextcloud is the first-class target, but not the only possible WebDAV server forever.

Rules:
- prefer plain WebDAV operations over vendor SDKs unless a strong reason exists
- support explicit server URL plus username plus app password
- recommend app passwords for Nextcloud instead of account passwords
- keep the remote root configurable even if the UI provides a Nextcloud default
- create required remote folders safely and idempotently
- do not assume all servers expose the same XML properties
- if using Nextcloud-specific metadata such as collection tags, always keep a generic fallback path

Avoid:
- hard-coding Nextcloud-specific URLs deep inside business logic
- coupling sync correctness to Nextcloud-only extensions
- assuming remote timestamps are trustworthy enough to resolve conflicts

## 9. Credential And Secret Rules

Credential handling is security-sensitive even though this is not an encryption project.

Rules:
- secrets belong in secure storage, not plain preferences or SQLite
- connection config and secret storage should be clearly separated
- avoid logging credentials, auth headers, or full WebDAV URLs with embedded credentials
- `Disconnect` must clear secrets without deleting local notes
- failed authentication must not corrupt local state

## 10. Code Organization Expectations

Prefer a structure that separates:
- presentation
- application/use-case logic
- persistence
- sync/backend integration
- credential management

Avoid:
- widget-driven business logic
- raw WebDAV calls inside UI components
- sync conditionals scattered across unrelated files
- provider-specific assumptions leaking into domain models unless reviewed

## 11. Testing Expectations

Agents should add or update tests when behavior changes.

Priority areas:
- repository logic
- sync reconciliation logic
- migration tests
- serialization tests
- stale-device and delete-resurrection scenarios
- conflict scenarios across devices
- clock-skew scenarios
- malformed WebDAV response handling
- auth failure and reconnect behavior
- attachment sync behavior

If tests are not added, the reason should be explicit.

Minimum expectation for backend changes:
- unit tests for parsing and mapping
- gateway tests for request behavior
- application-layer sync tests
- migration coverage when schema changes

## 12. Dependency Rules

Do not add dependencies casually.

Before introducing a package, check:
- whether Flutter/Dart stdlib already covers the need
- whether `http` plus a small XML parser is enough
- whether the package is maintained
- whether it adds platform-specific risk
- whether it increases lock-in around sync or storage

Prefer small, boring, well-maintained packages.

Avoid adding a large Nextcloud-specific SDK unless the capability gap is real and documented.

## 13. Change Management

When making meaningful architectural changes:
- update the relevant docs
- keep implementation aligned with `PLAN.MD`
- call out any divergence between the codebase and the migration plan

When replacing Google-era code:
- remove obsolete vocabulary when practical
- do not leave Drive-specific behavior hidden behind misleading generic names if it changes correctness assumptions
- preserve upgrade safety for existing local databases

## 14. Delivery Style

Agents working in this repo should optimize for:
- correctness over speed
- clear boundaries over clever abstractions
- boring reliability over premature sophistication
- explicit failure handling over optimistic assumptions

This project does not need impressive architecture. It needs architecture that survives real note data and unreliable networks.
