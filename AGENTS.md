# AGENTS.md

This file defines the working rules for coding agents contributing to Proper Notes.

## 1. Project Summary

Proper Notes is a local-first note-taking app for Linux desktop and Android.

Current v1 direction:
- Flutter app
- Dart 3.x
- Drift over SQLite for local persistence
- Google Drive `appDataFolder` as the initial sync backend
- Manual sync first, background sync later
- Logical folders in local app state
- A single text-note model, with copy-friendly code snippets planned as an editor/presentation feature rather than a rich block editor

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

## 3. v1 Scope

In scope:
- plain text or markdown note content
- note create, edit, delete, restore
- nested folders with move and rename flows
- local search and ordering
- Google account linking
- manual sync
- conflict-safe sync behavior
- code snippets as text-preserving note content, if implemented without turning v1 into a rich block editor

Out of scope for v1 unless explicitly requested:
- collaboration
- shared notebooks
- rich block editor
- end-to-end encryption
- web app
- multi-backend sync support in the product surface

## 4. Architecture Rules

Agents must preserve these constraints:

- UI code must not talk directly to Google Drive APIs.
- Remote sync logic must sit behind a sync interface.
- Note identity must use app-owned UUIDs, not file paths or Drive ids.
- Remote file ids are cache metadata only, never canonical identity.
- Reconciliation must not depend primarily on wall-clock timestamps.
- `updated_at` is for UX, sorting, and debugging, not correctness.
- Sync decisions should be based on state such as `content_hash`, `base_content_hash`, sync metadata, and explicit deletion state.
- Deletions must use tombstone semantics before any final purge.
- Missing remote files must be treated cautiously because absence is ambiguous.
- New code snippet behavior should stay over the existing note content string unless `PLAN.MD` explicitly introduces a reviewed migration.

## 5. Data Safety Rules

If a change risks data loss, stop and redesign it.

Required safety behavior:
- never overwrite conflicting edits without preserving both versions
- never hard-delete local notes immediately after a remote delete action
- never assume a device clock is correct
- never treat sync retries as one-shot operations
- never introduce schema changes without a migration plan

When uncertain, prefer:
- duplicate note over lost note
- conflict flag over silent merge
- explicit sync state over inferred state

## 6. Database Rules

Database choices should optimize long-term reliability and debuggability.

Rules:
- Drift is the default persistence layer for v1
- SQLite schema changes must be explicit
- migrations must be reviewed carefully
- migration tests are required for non-trivial schema changes
- avoid storing critical state only in memory if it is needed for sync recovery

Expected note metadata includes:
- `id`
- `title`
- `content`
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

## 7. Sync Rules

The sync engine is a safety-critical subsystem.

Agents must follow these rules:
- use manual/foreground sync as the baseline before background sync work
- keep sync logic separate from UI widgets
- treat Google Drive as transport/storage, not source of truth
- prefer delta sync with Drive change tokens over repeated full scans
- preserve enough metadata locally to recover from partial sync failures
- ensure sync operations are idempotent where possible
- design for stale devices returning after long offline periods

Minimum conflict posture:
- detect local-only changes
- detect remote-only changes
- detect concurrent changes
- preserve both versions when concurrent changes cannot be resolved safely

## 8. OAuth Rules

Linux OAuth can be brittle. Agents should not assume the happy path always works.

Rules:
- use system-browser auth flows
- support loopback redirect capture where appropriate
- provide a fallback manual auth-code path if loopback capture fails
- avoid coupling authentication flow tightly to UI screens

## 9. Code Organization Expectations

Prefer a structure that separates:
- presentation
- application/use-case logic
- persistence
- sync/backend integration

Avoid:
- widget-driven business logic
- Drive API calls inside UI components
- sync conditionals scattered across unrelated files

## 10. Testing Expectations

Agents should add or update tests when behavior changes.

Priority areas:
- repository logic
- sync reconciliation logic
- migration tests
- serialization tests
- stale-device and delete-resurrection scenarios
- conflict scenarios across devices
- clock-skew scenarios

If tests are not added, the reason should be explicit.

## 11. Dependency Rules

Do not add dependencies casually.

Before introducing a package, check:
- whether Flutter/Dart stdlib already covers the need
- whether the package is maintained
- whether it adds platform-specific risk
- whether it increases lock-in around sync or storage

Prefer small, boring, well-maintained packages.

## 12. Change Management

When making meaningful architectural changes:
- update the relevant docs
- keep implementation aligned with `PLAN.MD`

If code and plan diverge, call it out explicitly instead of silently drifting the architecture.

## 13. Delivery Style

Agents working in this repo should optimize for:
- correctness over speed
- clear boundaries over clever abstractions
- boring reliability over premature sophistication

This project does not need impressive architecture. It needs architecture that survives real note data.
