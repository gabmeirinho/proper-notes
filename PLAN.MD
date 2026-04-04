# Technical Plan: Proper Notes v1

An implementation plan for a private, offline-first note-taking app targeting Linux desktop and Android.

## 0. Status Snapshot

Current project state as of April 2026:

Working baseline:
- local-first notes with create, edit, delete, restore, and search
- conservative local autosave with lifecycle/close flushing
- Linux and Android sign-in
- manual sync with Drive delta tokens and conflict-copy preservation
- nested folders with folder-based filtering and subtree-aware deletion
- single-surface markdown editor with inactive-line rendering for headings, bullets, quotes, and fenced code blocks
- desktop workspace with notes nested in a collapsible folder tree, trash in the sidebar, and a slim top toolbar
- sidebar sync-state indicators and dismissible sync notices
- lighter mobile layout with oversized status banners removed
- release-candidate baseline already validated on Linux and Android

Still remaining before calling v1 done:
- persist desktop sidebar collapse state and expanded-folder state locally
- continue tightening the desktop editor spacing and typography
- add markdown task-list support in a way that does not destabilize the editor
- add more automated coverage for stale-device and broader integration scenarios
- complete folder management with stable rename / move flows
- decide the minimum release packaging/distribution process
- decide whether to cut `v0.1.0-rc2` or finalize `0.1.0`

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
- Markdown-first writing experience with stronger desktop note-taking ergonomics
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

Near-term product direction:
- keep SQLite as the local source of truth
- keep markdown as the note body format
- move the UX toward an Obsidian-like workspace feel
- add logical folders in app state instead of switching v1 to a filesystem vault model
- keep the editing surface as a normal text editor, not a block editor
- allow selective live rendering only where caret behavior stays reliable

### Current editor direction

The current editor direction is intentionally narrower than a full Obsidian clone:

- keep one plain markdown text editor as the editing surface
- do not use a split preview pane as the main editing experience
- do not use line-by-line block editing
- live-render only markdown constructs that behave reliably inside Flutter text editing

Current implementation status:

- headings, simple bullet markers, quote markers, and fenced code blocks are rendered in-place on inactive lines
- the active line remains raw markdown while editing
- note persistence is now local-first autosave rather than explicit-save-driven
- autosave should remain local-only; sync must stay outside the editing loop

This is a pragmatic v1 tradeoff. If richer in-editor rendering is revisited later, it should happen only with proof that caret, selection, and platform IME behavior remain stable.

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

- `folders`
- `folder_tree`
- `note_revisions`
- `tags`
- `note_tags`

These are not required for the current sync baseline, but the schema should not block them.

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
- Support keyboard shortcuts, context menus, desktop-friendly list navigation, and a sidebar-oriented workspace feel.
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

### Completed baseline

These areas are already implemented enough to stop planning them as open work:

- local app foundation
- current Linux and Android auth flows
- manual sync baseline with Drive delta sync
- first release-candidate baseline for `v0.1.0-rc1`
- initial folder model and folder filtering
- current single-surface markdown editor direction

### Phase 1: Editor UX hardening

Status: In progress

Goal:
- make everyday markdown writing feel more intentional without reintroducing caret instability

Scope:
- keep the current single-surface editor as the primary writing experience
- keep the active line raw markdown while editing
- replace manual-save-only persistence with conservative local autosave to SQLite
- tighten typography, spacing, and inactive-line rendering polish
- verify cross-platform caret behavior for headings, bullets, quotes, and fenced code blocks
- decide whether automatic list continuation on `Enter` is desirable or whether explicit toolbar/shortcut insertion is safer

Acceptance:
- a user can type, pause briefly, and trust that the note is persisted locally without pressing `Save`
- closing the editor, popping the route, or backgrounding the app flushes pending local edits before the view is discarded where platform constraints allow it
- autosave never creates duplicate notes from one editing session
- opening and closing a blank new-note editor without typing does not create empty note records
- no new cursor-jump, selection, or IME regressions on Linux or Android
- the editor remains trustworthy for long notes, multiline lists, and fenced code blocks

Concrete implementation order:
1. Introduce an editor-local autosave coordinator inside `NoteEditorPage` that tracks dirty state, last persisted snapshot, debounce timer, and in-flight save state.
   This should be a local UI/application concern, not sync logic, and it should not require a schema migration because the current notes table already stores the needed note state.
2. Define the autosave trigger policy before wiring persistence:
   use a short inactivity debounce for normal typing, plus immediate flush on editor close, route pop, focus loss where reliable, and app lifecycle transitions such as `inactive` / `paused`.
3. Split persistence behavior between existing notes and brand-new notes:
   existing notes should call `updateNote` when the current snapshot differs from the last persisted snapshot;
   new notes should call `createNote` only after the draft becomes meaningfully non-empty so the app does not generate junk empty notes.
4. After the first autosave of a new note, promote the editor session from "draft" to "persisted note" state using the returned `Note`.
   This is required so later autosaves call `updateNote` instead of creating duplicates, and so the desktop workspace can keep the correct selected note identity.
5. Serialize save operations and coalesce edits made during an in-flight save.
   If the user keeps typing while a save is running, the editor should mark itself dirty again and run one more save afterward instead of overlapping writes.
6. Keep sync out of the autosave loop.
   Autosave writes only to SQLite and updates normal note metadata such as `updated_at`, `content_hash`, and `sync_status`; remote sync remains manual and continues to read from the local database afterward.
7. Replace the current primary `Save` affordance with autosave status UI once the persistence path is stable.
   During rollout it is acceptable to keep an explicit save/flush or retry action, but it should stop being the user's primary responsibility.
8. Run a focused manual regression pass for autosave, headings, bullets, quotes, and fenced code on Linux and Android.
9. Clean up editor spacing, typography, and save-status presentation only after autosave semantics are stable.
10. Decide and document the `Enter` behavior for lists and quotes before implementing task lists.
11. Add targeted widget/unit coverage for autosave and any new editor rendering paths before broadening markdown support.

Deliverables:
- a conservative local autosave system for create and edit flows
- an editor session model that can safely transition from unsaved draft to persisted note
- save-status feedback that is quiet in normal operation and explicit on failure
- a stable editor baseline with documented caret behavior
- tests covering the known cursor-jump failure cases already found during development

### Phase 2: Workspace UX and folders

Status: In progress

Goal:
- make Proper Notes feel like a real desktop note workspace, not just a list plus editor

Desktop workspace plan:
- keep the folder sidebar visible while editing notes on desktop
- add a clear collapse/expand control for the sidebar instead of forcing a separate navigation step
- show notes inside the desktop sidebar tree under their current folder so the workspace feels navigable while writing
- allow each folder section to collapse and expand
- persist sidebar open state and expanded-folder state locally
- keep folder rows unselected so the active note, not the active folder, carries the main visual highlight

Folder clarity plan:
- make the current location obvious with a breadcrumb or path chip near the editor title instead of relying on a large top banner
- highlight the selected folder more strongly in the sidebar and the note list
- show empty-state copy that clearly reflects the current folder context

Folder management still missing:
- rename folders
- move notes between folders
- consider move/rename affordances that work on both desktop and Android without duplicating logic

Acceptance:
- a desktop user can understand where they are, navigate folders while editing, and collapse unused parts of the tree without losing context

Concrete implementation order:
1. Restructure the desktop layout so the sidebar can remain visible while a note editor is open.
   Current state: done.
2. Add a desktop-only sidebar collapse/expand control and persist its state locally.
   Current state: collapse/expand control exists; persistence is still pending.
3. Replace the current flat folder list behavior with expandable folder groups that can remember expanded state.
   Current state: expandable folder groups exist; remembering state across launches is still pending.
4. Add note rows under the active folder sections in the desktop sidebar so the tree reflects both folders and notes.
   Current state: done.
5. Strengthen current-folder highlighting and add a compact breadcrumb/path treatment near the note list or editor header.
   Current state: desktop and mobile no longer use the older large folder banners; mobile folder context now lives in the app bar.
6. Add rename-folder and move-note flows only after the navigation structure is stable.
   Current state: implementation has started in the worktree, but it is not yet complete and should be treated as in-progress until tests are green.

Dependencies:
- Phase 2 should land before the broader status/chrome redesign because the new workspace header needs to know where folder context lives.

Deliverables:
- persistent sidebar visibility/collapse state
- collapsible folder tree with note visibility
- clearer current-folder context in both navigation and content areas

### Phase 3: Status and chrome redesign

Status: In progress

Goal:
- reduce the current top-of-screen warning-strip feel and replace it with calmer, denser status UI

Design direction:
- remove the large full-width sync and folder banners from the main content column
- move sync state into a compact status row, toolbar badge, or contextual header chip set
- move folder context into the note list/editor header as part of navigation, not as a warning panel
- reserve stronger surfaces or banners only for exceptional states such as sync errors, conflicts, or auth problems

Suggested target layout:
- top app bar keeps global actions
- below it, a compact workspace header carries current folder, sync state, and maybe note count
- regular background surfaces stay visually quiet so notes remain the focus

Acceptance:
- normal states such as "Sync ready" or "Folder: X" should no longer dominate the screen
- error states should still remain explicit and hard to miss

Concrete implementation order:
1. Remove the large folder banner and move folder context into a compact workspace header.
   Current state: done for the current UI direction. Desktop uses a slim workspace top bar, and mobile now carries folder context in the app bar instead of a full-width banner.
2. Replace the passive "Sync ready" container with a compact status chip/badge near the toolbar or workspace header.
   Current state: still pending.
3. Keep success/info states visually quiet and reserve larger surfaces for errors, conflicts, or auth blockers.
   Current state: partly done on desktop, still heavier on mobile.
4. Review the desktop and narrow/mobile layouts so the new header scales without adding clutter.
   Current state: significantly better on mobile than the earlier banner-heavy version, but the small-screen navigation model still needs refinement.
   Current state: ongoing.
5. Only after the structure is stable, refine color, spacing, and iconography.

Dependencies:
- Phase 3 should build on the Phase 2 workspace shell rather than redesigning the current temporary banners in place.

Deliverables:
- compact workspace header
- reduced top-of-screen noise
- clearer separation between normal status and exceptional status

### Phase 4: Markdown task lists

Status: Planned

Goal:
- support checkbox-style markdown without turning the editor into a block editor

Scope:
- support `- [ ] item` and `- [x] item` syntax as stored markdown text
- render inactive task-list lines with clear checked and unchecked visuals
- render task lists in note previews and read surfaces
- decide whether tapping a checkbox should directly rewrite markdown text or whether v1 should keep interaction keyboard/text-first

Safety rules:
- the underlying stored content must remain plain markdown text
- toggling checkbox state must be deterministic and test-covered
- task-list rendering must not break caret movement, especially around `Enter`, Backspace, and multiline items

Acceptance:
- task lists display clearly in list previews and in the editor on inactive lines
- task-list edits round-trip cleanly through sync and conflict handling because they are still just markdown text

Concrete implementation order:
1. Extend markdown parsing/rendering in previews for `- [ ]` and `- [x]`.
2. Extend inactive-line editor rendering for task-list lines while keeping the active line raw markdown.
3. Add parser and rendering tests for checked, unchecked, and multiline task-list items.
4. Decide whether checkbox tapping is in scope for v1 or whether task lists remain text-edited only.
5. If tapping is allowed, implement deterministic markdown text rewriting with explicit tests for cursor and selection safety.

Dependencies:
- task lists should start only after the editor baseline from Phase 1 is considered stable.

Deliverables:
- task-list preview support
- task-list editor rendering support
- a documented decision on interactive checkbox toggling

### Phase 5: Reliability hardening before final v1

Status: In progress

- automated regression coverage for restore, stale-device, and tombstone-retention scenarios
- more integration-level coverage for cross-device editing and auth/session recovery
- repeat targeted manual QA only when sync/editor logic changes land

Concrete implementation order:
1. Add the highest-risk missing sync tests before any release decision.
2. Add regression coverage for the new workspace and editor UX where behavior can break silently.
   Autosave coverage should include debounce save, flush-on-close, flush-on-lifecycle-change, no-empty-note creation, and no-duplicate creation after the first persisted draft save.
3. Re-run targeted manual QA on Linux and Android after each user-facing markdown/editor or navigation milestone.

### Phase 6: Packaging and release decision

Status: Planned

- define the minimum Linux install/distribution flow to support the first stable release
- decide whether the current scope is enough for `v0.1.0-rc2` or final `0.1.0`
- keep background sync and heavier release automation out of scope until the core workspace/editor UX is stable

Release gate for the current UX roadmap:
1. Phase 1 editor stability is clean on Linux and Android.
2. Phase 2 desktop workspace/navigation is implemented and feels coherent.
3. Phase 3 status/chrome redesign removes the current banner-heavy feel.
4. Phase 4 task lists are either implemented safely or explicitly deferred with the decision recorded.
5. Reliability coverage is good enough that the new UX work has not weakened data safety.

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
- migration test groundwork now exists for the current schema
- focused autosave widget coverage now exists, but broader editor regression coverage is still limited
- broader integration coverage is still mostly manual via the QA checklist, and the latest full manual pass succeeded on release builds

## 14. Future Extensions

Possible post-v1 features:
- tags and notebooks
- pinned notes
- note history
- attachments
- optional end-to-end encryption
- pluggable sync backends
- richer inline markdown editing if the simpler editor still feels too limited
- optional filesystem vault import/export if the product later needs Obsidian interoperability

## 15. Final Recommendation

For v1, the most defensible path is:

- Flutter for cross-platform UI
- Drift + SQLite for local persistence
- Google Drive `appDataFolder` as a temporary sync backend
- manual sync first
- conflict-safe behavior instead of aggressive overwrite logic

The app should earn trust through reliability first. Background automation and packaging should come after the local data model and sync engine are proven stable.
