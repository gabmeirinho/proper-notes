# ARCHITECTURE.md

This document defines the intended system architecture for Proper Notes v1.

It exists to keep implementation aligned with the product plan and architectural decisions already recorded in:
- `PLAN.MD`
- `DECISIONS.md`
- `AGENTS.md`

## 0. Current Implementation Status

Current implementation status as of March 2026:
- the local-first note model is implemented
- Linux and Android both run from the same Flutter codebase
- notes, deleted notes, restore, and search are implemented
- manual sync with Google Drive `appDataFolder` is implemented
- delta sync via Drive change tokens is implemented
- conflict preservation is implemented via duplicate conflict-copy notes
- the architecture below is no longer only aspirational in the main v1 areas; most of the remaining work is reliability hardening, test coverage, and release discipline

## 1. Architectural Goals

The architecture should optimize for:
- offline-first reliability
- clear separation between editing and sync
- safe conflict handling
- debuggable persistence and sync behavior
- future extensibility without destabilizing v1

The architecture should not optimize for:
- premature abstraction
- multi-backend feature richness in v1
- collaboration features
- AI features in the initial implementation

## 2. Core Architectural Principle

The local database is the source of truth.

Everything else is downstream of that rule:
- the UI reads from local state
- the UI writes to local state
- sync reads local state and reconciles with remote state
- remote state must not directly drive UI state without passing through local persistence

This avoids network-coupled editing behavior and keeps the product usable offline.

## 3. High-Level Layers

The codebase should be organized into four main layers:

1. Presentation layer
2. Application layer
3. Data layer
4. Platform/integration layer

### 3.1 Presentation Layer

Responsibilities:
- screens
- widgets
- local interaction state
- rendering note lists, editor views, settings, sync status, and auth state

Rules:
- no direct database queries from widgets
- no direct Google Drive API calls
- no sync reconciliation logic
- UI should react to view models, streams, or use-case outputs

### 3.2 Application Layer

Responsibilities:
- use cases
- orchestration of note operations
- orchestration of sync execution
- conflict handling flows
- auth/session coordination

Examples:
- `CreateNote`
- `UpdateNote`
- `DeleteNote`
- `RestoreNote`
- `SearchNotes`
- `RunManualSync`
- `ResolveConflict`
- `SignInWithGoogle`

Rules:
- application logic depends on interfaces, not storage details
- this layer decides what should happen, not how Flutter widgets render it

### 3.3 Data Layer

Responsibilities:
- persistence via Drift/SQLite
- note repository
- metadata repository
- sync state persistence
- remote DTO serialization
- Drive gateway implementation

Subareas:
- local data sources
- remote data sources
- repositories
- mappers/serializers

Rules:
- keep schema and repository logic here
- separate local persistence concerns from remote transport concerns

### 3.4 Platform/Integration Layer

Responsibilities:
- OAuth browser launch and redirect capture
- Android background job integration
- platform storage path resolution
- network reachability or device constraints if later needed

Rules:
- isolate platform-specific behavior behind interfaces where possible
- avoid leaking platform implementation details into business logic

## 4. Proposed Module Boundaries

The exact folder structure can evolve, but the boundaries should stay stable.

Suggested top-level organization:

```text
lib/
  app/
  core/
  features/
    notes/
    auth/
    sync/
  infrastructure/
```

Suggested responsibilities:

- `app/`
  - app bootstrap
  - dependency wiring
  - routing
  - app-wide configuration

- `core/`
  - shared value objects
  - error types
  - result wrappers
  - utility services that are domain-agnostic

- `features/notes/`
  - note domain models
  - note repository contracts
  - note use cases
  - note UI

- `features/auth/`
  - auth models
  - auth service contracts
  - auth use cases
  - settings/account UI

- `features/sync/`
  - sync coordinator
  - reconciliation logic
  - sync state models
  - sync use cases
  - conflict handling models

- `infrastructure/`
  - Drift database setup
  - repository implementations
  - Drive client/gateway
  - OAuth integration
  - hashing
  - serialization

## 5. Primary Domain Entities

The initial architecture should revolve around a small set of explicit entities.

### 5.1 Note

Represents the canonical local note record.

Key fields:
- `id`
- `title`
- `content`
- `createdAt`
- `updatedAt`
- `deletedAt`
- `lastSyncedAt`
- `syncStatus`
- `contentHash`
- `baseContentHash`
- `deviceId`
- `remoteFileId`

### 5.2 App Metadata

Represents singleton or small-scope app state used by infrastructure and sync logic.

Key fields:
- `deviceId`
- signed-in account metadata
- `driveSyncToken`
- `lastFullSyncAt`
- `lastSuccessfulSyncAt`

### 5.3 Remote Note Payload

Represents the serialized note format stored in Google Drive.

Key fields:
- `id`
- `title`
- `content`
- `created_at`
- `updated_at`
- `deleted_at`
- `device_id`
- `content_hash`

### 5.4 Conflict Artifact

Represents a preserved concurrent-change result.

This can be implemented either as:
- a duplicated note entry with conflict metadata
- a revision entry
- a dedicated conflict table

For v1, the simplest acceptable implementation is a duplicate note copy plus `conflicted` state.

## 6. Data Flow

### 6.1 Normal Note Editing Flow

1. User edits a note in the UI.
2. Presentation layer sends an action to an application use case.
3. Use case updates the note through the repository.
4. Repository writes to SQLite.
5. Note metadata is updated:
   - `updatedAt`
   - `contentHash`
   - `syncStatus`
6. UI reacts to updated local state.

Important:
- editing must succeed without network access
- sync is not part of the edit transaction

### 6.2 Manual Sync Flow

1. User triggers sync or app startup decides a sync should run.
2. `RunManualSync` use case acquires a sync lock.
3. Sync coordinator loads:
   - local notes requiring reconciliation
   - app metadata including `driveSyncToken`
4. Drive gateway fetches remote changes.
5. Reconciliation engine compares local baseline state with remote state.
6. Sync actions are produced:
   - upload
   - download
   - delete propagation
   - conflict creation
   - no-op
7. Actions are applied in a controlled order.
8. SQLite is updated with the new sync baseline state.
9. Sync token and sync timestamps are persisted.
10. UI reflects final sync status from local state.

### 6.3 Auth Flow

1. User starts sign-in.
2. Auth service launches the system browser.
3. Loopback redirect is attempted.
4. If loopback fails, a fallback manual code flow is used.
5. Tokens/session metadata are stored securely.
6. Application layer exposes signed-in state to the UI.

## 7. Reconciliation Model

The reconciliation engine is a core architectural boundary.

It should be implemented as pure, testable logic as much as possible.

Primary comparison inputs:
- local `contentHash`
- local `baseContentHash`
- remote `contentHash`
- explicit deletion state

Secondary inputs:
- `updatedAt`
- remote modified timestamps

The secondary inputs are for diagnostics or tie-break support only. They should not be the main correctness model.

Expected outcomes:
- unchanged
- local upload
- remote download
- deletion propagation
- conflict preservation

## 8. Deletion Model

Deletion must be modeled as state, not only as absence.

Rules:
- user deletion marks a note with `deletedAt`
- deleted notes remain in local storage as tombstones for a retention window
- sync propagates deletion intent
- local purge happens later under a cleanup policy

Why:
- hard deletion creates ambiguity for stale devices
- remote absence alone is not enough to infer deletion safely

## 9. Sync State And Recovery

The architecture should assume sync can fail halfway.

Design implications:
- sync operations must be restartable
- local metadata must allow recovery after crash or app termination
- repeated sync attempts should converge rather than duplicate work
- partial remote success must not leave local state unrecoverable

Recommended patterns:
- explicit sync status values
- persisted sync checkpoints where useful
- a single sync coordinator entry point
- serialized sync execution to avoid overlapping runs

## 10. Dependency Direction

The dependency direction should stay predictable:

- presentation depends on application
- application depends on repository/service interfaces
- infrastructure implements those interfaces
- infrastructure may depend on Flutter plugins, Drift, Google APIs, and platform packages

Avoid the reverse:
- application depending directly on widget code
- presentation depending directly on Drive clients
- domain logic depending directly on platform APIs

## 11. Error Handling

Errors should be categorized rather than treated as generic failure.

Useful categories:
- validation errors
- local persistence errors
- auth/session errors
- remote API errors
- sync conflict conditions
- retryable network failures

Behavior expectations:
- editing errors should not be hidden
- sync failures should not destroy local edits
- conflict is a state to handle, not a generic exception

## 12. Observability

The app should provide enough visibility to debug sync behavior during development and support future troubleshooting.

At minimum:
- local sync status per note
- last successful sync time
- current auth/account state
- structured logs for sync steps in debug builds

Avoid:
- logging note content in plain text unless explicitly in a debug-only safe context

## 13. Future Extension Points

The architecture should keep room for future additions without polluting v1.

Likely future areas:
- note tags
- note history
- attachments
- alternative sync backends
- AI-derived artifacts such as summaries or embeddings

Guideline:
- future features should attach to stable note identity and repository interfaces
- derived artifacts should not replace canonical user-authored note content

## 14. Non-Negotiable Constraints

These constraints should hold unless a deliberate architectural decision replaces them:

- local DB is authoritative
- no direct UI-to-Drive calls
- no timestamp-driven overwrite logic
- no silent conflict destruction
- no immediate hard-delete semantics for synced notes
- no background sync work before manual sync is trustworthy

## 15. Implementation Order

Recommended implementation order:

1. App bootstrap and dependency wiring
2. Drift schema and database setup
3. Note repository and local CRUD
4. Notes UI on top of local state
5. Auth service integration
6. Drive gateway and serialization
7. Reconciliation engine
8. Manual sync coordinator
9. Conflict UX
10. Background sync and packaging

This order is intentional. It validates the local product before layering in the most failure-prone parts.

Current status against this order:
- steps 1 through 9 are substantially implemented
- step 10 remains mostly future work, aside from a basic Linux launcher/install path and manual release-build validation
