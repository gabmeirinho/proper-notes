# ARCHITECTURE.md

This document describes the current architecture of Proper Notes and the intended near-term direction.

## Current Implementation Status

Current implementation status as of April 2026:
- Linux and Android both run from one Flutter codebase
- SQLite via Drift is the local source of truth
- schema version `2` adds logical folders through `folder_path` plus a `folders` table
- note create, edit, delete, restore, search, and autosave are implemented
- manual sync with Google Drive `appDataFolder` is implemented
- delta sync using Drive change tokens is implemented
- conflict preservation is implemented through duplicate conflict copies
- folder create, rename, move, drag-and-drop, and subtree-aware delete flows are implemented
- the desktop app uses a sidebar-first workspace with an embedded editor
- the preview layer no longer has dedicated fenced code block support
- the editor still contains fence-based code insertion and fenced inactive-line styling

## Core Rules

These rules remain non-negotiable:
- the local database is the source of truth
- UI code must not talk directly to Google Drive APIs
- remote file ids are cache metadata, not canonical note identity
- sync correctness must not depend primarily on wall-clock timestamps
- deletions must use tombstones before any purge policy
- conflict preservation is more important than aggressive auto-merge

## Layering

The current codebase is organized around these layers:

### Presentation

Responsibilities:
- app screens and widgets
- note list, workspace, editor, search, account sheet, and sync notices
- markdown preview and editor-specific rendering behavior

Rules:
- no direct Drive API usage from widgets
- no persistence logic embedded in UI event handlers beyond use-case calls

### Application

Responsibilities:
- note and folder use cases
- sync orchestration entrypoints
- auth state coordination

Current examples:
- `CreateNote`
- `UpdateNote`
- `DeleteNote`
- `RestoreNote`
- `CreateFolder`
- `RenameFolder`
- `MoveNote`
- `RunManualSync`

### Infrastructure

Responsibilities:
- Drift database and migrations
- repository implementations
- Google auth integration
- Google Drive sync gateway
- content hashing and low-level persistence details

### Platform Integration

Responsibilities:
- Linux desktop OAuth browser flow and loopback callback capture
- Android Google Sign-In integration
- filesystem paths, secure storage, launcher/install packaging

## Data Model

### Note

The note remains the canonical local record.

Important fields currently in use:
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
- `folderPath`
- `remoteFileId`

### Folder

Folders are logical application state, not filesystem paths.

Important fields:
- `path`
- `parentPath`
- `createdAt`

### App Metadata

The app metadata row stores recovery-critical singleton state:
- `deviceId`
- account email
- `driveSyncToken`
- `lastFullSyncAt`
- `lastSuccessfulSyncAt`

## Sync Model

Manual sync is the trusted baseline.

The current sync model is:
1. edit locally first
2. persist to SQLite
3. update sync metadata locally
4. run sync separately through `RunManualSync`
5. reconcile local and remote state using hashes, tombstones, and baseline metadata

Primary reconciliation inputs:
- local `contentHash`
- local `baseContentHash`
- remote `contentHash`
- explicit deletion state

Secondary inputs:
- `updatedAt`
- remote modified timestamps

Secondary inputs may help diagnostics, but they are not the main correctness model.

## Editor Model

The editing surface is intentionally conservative:
- one text editor remains the source of truth for note content
- autosave persists locally and does not trigger sync inline with editing
- the active line stays raw text

Current inactive-line rendering behavior:
- headings are visually restyled
- bullet markers are visually replaced with a bullet glyph
- quote markers are visually restyled
- fenced code is still visually styled inside the editor only

This means the current code experience is inconsistent:
- the editor still inserts and styles triple-backtick regions
- the preview layer no longer renders dedicated fenced code blocks

## Markdown Preview Model

The compact preview used in the note list currently supports:
- headings
- paragraphs
- lists
- block quotes
- dividers
- inline bold
- inline italic
- inline code

The preview intentionally no longer treats triple backticks as a special block type.

## Planned Code Snippet Direction

The next editor-format change should not reintroduce markdown fenced-code parsing as the main solution.

Planned architectural direction:
- keep note content in the existing single `content` text field
- implement code snippets as an editor/presentation convention over that text
- avoid introducing a separate snippet table or block-editor architecture for v1
- render snippet content without markdown interpretation inside the snippet body
- provide a copy-friendly workflow without weakening offline reliability or sync safety

`PLAN.MD` now documents the concrete implementation plan for that mechanism.

## Testing Priorities

Current automated coverage already exists for:
- repositories
- schema migration to version `2`
- auth controller behavior
- Drive sync gateway behavior
- sync controller/use-case behavior
- markdown preview behavior
- editor autosave behavior
- workspace and folder UI flows

Still important to expand:
- stale-device sync scenarios
- delete resurrection scenarios
- broader end-to-end sync regression coverage
- future code snippet parsing, rendering, and copy flows
