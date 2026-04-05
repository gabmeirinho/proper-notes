# NEXT_STEPS.md

This file is the short handoff for the next agent or chat session.

## Current State

Proper Notes currently has:
- local-first notes on Linux and Android
- manual Google Drive sync with delta-token support
- conflict-copy preservation across devices
- schema version `2` with logical folders
- folder create, rename, move, drag-and-drop, and subtree-aware delete flows
- desktop embedded editing with autosave
- compact markdown previews in the note list
- a tagged release candidate: `v0.1.0-rc1`
- a green `flutter test` run in the current workspace

## Important Current Editor Reality

The current code-related behavior is in transition:
- the editor still inserts fenced code blocks with triple backticks
- inactive editor lines still style fenced code regions
- the markdown preview no longer renders fenced code blocks as a dedicated block type
- there is no first-class code snippet UX yet

That mismatch should be treated as the next product-shaping task, not as a small polish item.

## Immediate Next Work

The next meaningful implementation should be the code snippet mechanism described in `PLAN.MD`.

Recommended order:
1. Replace fence-based code insertion with the new snippet delimiters and insertion command.
2. Add snippet parsing and rendering to the compact preview layer without interpreting snippet contents as markdown.
3. Remove or replace the remaining fence-specific inactive-line editor behavior.
4. Add focused parser, preview, editor, autosave, title-derivation, and sync round-trip tests.
5. Run a targeted manual QA pass for snippet insertion, editing, copy flows, and sync preservation.

## After That

Once code snippets are stable, the best next items are:
- persist desktop sidebar collapse state and expanded-folder state locally
- add more stale-device and migration-oriented sync coverage
- tighten release packaging and release notes for the first stable build

## Current Worktree Note

At the time this handoff was updated, the worktree already contained:
- fenced code block preview removal in `markdown_preview.dart`
- matching markdown preview test updates
- documentation updates reflecting the current state and the new snippet plan

Before unrelated work, inspect `git status` and decide whether to commit or reshape that set intentionally.
