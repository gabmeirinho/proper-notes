# NEXT_STEPS.md

This file is the short handoff for the next agent or chat session.

## Current State

Proper Notes currently has:
- working local-first notes on Linux and Android
- working manual sync using Google Drive `appDataFolder`
- working cross-device create, edit, delete, restore, and conflict-copy behavior
- local-first autosave for note create/edit flows
- a public repository
- a tagged first release candidate: `v0.1.0-rc1`
- persisted per-install device identity
- migration-test groundwork
- small sync/account UX polish

The current product direction has shifted from "minimal synced notes app" toward:
- an Obsidian-like workspace feel
- markdown-first writing UX
- logical nested folders in app state
- SQLite still as the source of truth
- no filesystem vault model for v1

## Important Current Workspace State

There is active uncommitted work in the tree right now.

The current uncommitted implementation includes:
- folder-aware schema and migration to schema version `2`
- logical nested folders via `folder_path`
- folder repository and folder creation flow
- folder sidebar/sheet and folder-based note filtering
- desktop sidebar tree with collapsible folders and nested note rows
- desktop trash entry inside the workspace/sidebar instead of a top tab
- desktop sidebar collapse/expand control in the slim top toolbar
- subtree-aware folder deletion with confirmation for non-empty folders
- desktop right-click / long-press context actions for notes and folders
- note sync payload support for `folder_path`
- a single markdown text editor as the primary editing model
- live in-place heading, bullet, quote, and code-block rendering for inactive lines
- keyboard shortcuts for heading/list/quote/code insertion
- desktop embedded editor with a flatter, less boxed writing surface
- autosave with debounce plus close/lifecycle flushes
- sidebar note sync-state icons and dismissible sync notices
- lighter mobile UI with the old large folder/sync/shortcuts boxes removed

Important current editor reality:
- do not reintroduce a split preview panel in the editor
- do not revive the earlier line-by-line inline editor experiment
- headings, simple bullet markers, quote markers, and fenced code blocks are intentionally active in the editing surface on inactive lines right now
- the active editing line should still remain raw markdown unless a more robust editor architecture is introduced
- desktop embedded mode intentionally hides the H1/H2/H3/list/quote/code button row to keep the writing surface minimal

Before doing unrelated work, inspect `git status` and decide whether to:
- commit the current folder/editor work
- refine it further
- or discard/reshape part of it intentionally

Do not assume the worktree is clean.

## Active In-Progress Work

There is partially implemented work in the tree for:
- renaming folders
- moving notes between folders

Do not assume that feature is finished just because the new files and wiring exist.

Current known state of that in-progress work:
- repository/use-case pieces for folder rename and note move have been added
- `notes_home_page.dart` has partial UI wiring for both flows
- focused repository tests were green the last time they were run
- widget tests were still failing because the move/rename dialogs used `TextEditingController` disposal patterns that race the dialog lifecycle
- one existing widget test around trash/navigation also needed to be updated to match the current workspace UI instead of the older top-tab assumptions

If you pick that work back up, start by fixing the dialog lifecycle issue and then rerun:

```bash
flutter test test/features/notes/application/note_use_cases_test.dart \
  test/infrastructure/repositories/drift_folder_repository_test.dart \
  test/features/notes/presentation/notes_home_page_test.dart
```

## Immediate Next Steps

The next work should be product-shaping, not sync-architecture work:

1. Finish and stabilize folder rename / note move.
   Focus on:
   - dialog lifecycle correctness
   - desktop and mobile affordances for move/rename
   - preventing broken selection/expanded-state updates after folder rename

2. Review the current folder and heading-rendered editor implementation in the app itself.
   Likely options:
   - whether heading rendering feels good enough to keep
   - whether list / quote / code should intentionally stay raw while editing
   - whether the current folder actions are enough for daily use

3. Stabilize the workspace direction after that:
   - persist sidebar collapse and expanded-folder state locally
   - refine desktop spacing, typography, and hover states
   - keep narrowing mobile chrome and navigation complexity

## What Not To Do Next

Do not start with:
- background sync
- WorkManager integration
- a filesystem markdown vault migration
- a new auth architecture
- large sync refactors without a newly reproducible bug

Those are explicitly later unless a real regression forces them.

## Release Gate Status

The current QA gate has already been passed manually on Linux and Android release builds.

`v0.1.0-rc1` exists and the repo is public, but the current working tree has moved past that tag and includes uncommitted product-direction work.

Before changing sync logic again, prefer:
- reproducing a new bug with exact steps
- recording sync summary text from both devices
- patching only the specific failing case

## Supporting Docs

Read these first:
- `README.md`
- `PLAN.MD`
- `QA_CHECKLIST.md`
- `ARCHITECTURE.md`
