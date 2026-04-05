# Release Notes

## Unreleased

Current work beyond `v0.1.0-rc1` includes:
- schema version `2` with logical folders
- folder create, rename, move, drag-and-drop, and subtree-aware delete flows
- desktop sidebar-first workspace with embedded editing
- local autosave with lifecycle and close flushing
- per-note sync-state indicators and dismissible sync notices
- lighter mobile chrome and folder context in the app bar
- compact markdown previews aligned with the current workspace UI

Current editor/code status:
- fenced code block preview support has been removed from the preview layer
- the editor still contains fence-based code insertion and fenced inactive-line styling
- a first-class code snippet replacement is planned in `PLAN.MD`

## v0.1.0-rc1

First release candidate for Proper Notes.

Included in this build:
- local-first note creation, editing, deletion, and restore
- Linux desktop and Android support from one Flutter codebase
- Google Drive `appDataFolder` manual sync
- conflict-safe sync behavior with conflict-copy preservation
- local search

Scope notes that still apply:
- sync is manual/foreground only
- background sync is intentionally deferred
- Google Drive is the initial sync backend for v1
