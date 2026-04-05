# Technical Plan: Proper Notes Block Document Architecture

This file replaces the previous short-term code snippet plan.

It defines the target architecture for Proper Notes if the product direction includes:
- first-class code blocks with permanent controls such as copy buttons
- pasted images that render inline in notes
- slash commands similar to Obsidian
- a more modern block-oriented editing experience
- future AI features without weakening local-first reliability or sync safety

## 1. Executive Summary

Proper Notes should keep its current local-first storage and sync foundations, but evolve the note body from a single raw text field into a versioned block document model.

What should stay:
- Flutter app
- Drift over SQLite
- local database as the source of truth
- note identity owned by the app
- sync behind interfaces
- conservative conflict preservation

What should change:
- the note body/editor architecture
- the way note content is stored and rendered
- the way attachments and rich blocks are represented

Recommended target:
- a hybrid block editor
- each note contains an ordered list of blocks
- text-like blocks remain simple
- code and image blocks become first-class widgets
- AI features operate on structured local content but remain derived, not canonical, unless explicitly accepted by the user

## 2. Product Goals

The new architecture should support:
- code blocks with always-visible copy buttons
- inline images that appear immediately after paste/import
- slash commands such as `/code`, `/image`, `/quote`, `/heading`
- richer visual design and more modern note composition
- future AI features such as summarize, rewrite, extract tasks, and semantic indexing

The new architecture must not break:
- offline-first editing
- local DB authority
- conservative sync behavior
- conflict preservation
- debuggability

## 3. Non-Negotiable Constraints

These constraints remain mandatory:
- the local database is the source of truth
- sync must never silently destroy user-authored content
- note identity must continue to use app-owned UUIDs
- remote ids remain cache metadata, never canonical identity
- wall-clock timestamps must not be the main correctness model for sync
- AI-generated content must not silently replace user content
- missing remote files remain ambiguous and must be handled conservatively

## 4. Architectural Direction

The app should move from:
- one note body string
- one main `TextField`
- lightweight markdown-like styling

to:
- one note containing a versioned structured document
- one ordered list of blocks
- one widget per block
- local serialization of the document
- derived projections for search, preview, and export

This is not a full Notion-like collaborative editor target.

It is a local-first hybrid block editor optimized for:
- reliability
- boring persistence
- attachments
- code blocks
- inline images
- future AI augmentation

## 5. Core Data Model

### 5.1 Notes Table

The `notes` table should remain the main record for note identity and sync metadata.

It should continue to own fields such as:
- `id`
- `title`
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

The note body storage should evolve.

Recommended direction:
- replace the current single `content` source-of-truth with a document field such as `document_json`
- optionally keep a derived `plain_text_cache` for search and preview generation

Transitional option:
- keep `content` during migration
- add `document_json`
- gradually move reads and writes to `document_json`
- remove or deprecate `content` only after migration is stable

### 5.2 Document Structure

Each note body should be stored as a JSON document.

Suggested shape:

```json
{
  "version": 1,
  "blocks": [
    {
      "id": "blk_1",
      "type": "heading",
      "level": 1,
      "text": "Title"
    },
    {
      "id": "blk_2",
      "type": "paragraph",
      "text": "Hello world"
    },
    {
      "id": "blk_3",
      "type": "code",
      "language": "dart",
      "code": "final a = 1;"
    },
    {
      "id": "blk_4",
      "type": "image",
      "attachment_id": "att_1",
      "caption": ""
    }
  ]
}
```

### 5.3 Block Identity

Each block must have a stable block id.

Why:
- reliable local editing state
- future block-level UI operations
- block-targeted AI suggestions
- more understandable diffing and reconciliation later

Rules:
- block ids must be app-owned UUID-like ids
- block order is explicit in the document
- block ids must survive edits that change content but not identity

### 5.4 Block Types

Minimum v1 block types for the new editor:
- `paragraph`
- `heading`
- `bullet_list_item`
- `quote`
- `code`
- `image`

Likely near-term additions:
- `checklist_item`
- `divider`
- `callout`

Do not introduce too many types initially.

Start with the types required for:
- plain writing
- code
- images
- slash commands

## 6. Attachments Model

### 6.1 Attachments Table

Images should not be stored inline in the note JSON as binary data.

Add an `attachments` table with fields such as:
- `id`
- `note_id` or nullable owner reference
- `mime_type`
- `local_path`
- `file_size`
- `width`
- `height`
- `sha256`
- `created_at`
- `updated_at`
- `deleted_at`
- `sync_status`
- `remote_file_id`

### 6.2 Local File Storage

Attachment binaries should live in app-managed local storage, not inside SQLite blobs unless there is a strong reason otherwise.

Recommended approach:
- store files under an app attachments directory
- keep SQLite for metadata only

Why:
- easier debugging
- easier file replacement and cleanup
- avoids bloating the database file

### 6.3 Image Blocks

Image blocks should reference attachments by id:

```json
{
  "id": "blk_4",
  "type": "image",
  "attachment_id": "att_1",
  "caption": "diagram"
}
```

This keeps note content structured and attachment lifecycle separate.

## 7. Editor Architecture

### 7.1 Editor Model

The editor should become a block editor, but still optimized for local simplicity.

Recommended structure:
- parse `document_json` into a local in-memory `NoteDocument`
- render one widget per block
- each editable block owns its own controller/focus state
- serialize the whole document back to JSON for autosave

Suggested in-memory model:

```text
NoteDocument
  version
  blocks[]

Block
  id
  type
  payload
```

### 7.2 Widget Strategy

Each block becomes a real widget:
- paragraph block widget
- heading block widget
- code block widget
- image block widget

This unlocks:
- permanent copy buttons on code blocks
- real inline image rendering
- per-block menus
- drag handles later if desired
- richer styling without pretending styled text is still one field

### 7.3 Editing Behavior

The editor must define:
- how Enter splits a block
- how Backspace merges blocks
- how slash commands insert or transform blocks
- how paste behaves in paragraph vs code vs image contexts

These behaviors should be explicit and tested.

Do not rely on ad hoc UI behavior.

### 7.4 Code Blocks

Code blocks should be first-class widgets with:
- monospace rendering
- optional language label
- always-visible copy button
- raw code persistence without markdown interpretation

Optional later:
- syntax highlighting
- collapse/expand

### 7.5 Images

When the user pastes an image:
1. save it as an attachment
2. create an image block at the insertion point
3. render the image immediately in the editor

This should be a real block, not a text token pretending to be an image.

### 7.6 Slash Commands

Slash commands become natural in a block editor.

Examples:
- `/code`
- `/image`
- `/quote`
- `/heading`
- `/divider`

Behavior:
- user types `/`
- show command picker near the caret
- choosing a command converts or inserts a block

## 8. Serialization and Derived Projections

The canonical body should be `document_json`.

Derived projections should be stored or computable for:
- search text
- note title derivation
- compact previews
- exports such as markdown/plain text later

Recommended derived fields:
- `plain_text_cache`
- `preview_text_cache`

Rules:
- derived fields are disposable and rebuildable
- canonical user-authored content remains the document JSON plus attachments

## 9. Search

Search should not depend on rendering widgets.

Recommended approach:
- flatten text-bearing blocks into searchable text
- store that in a derived searchable cache
- include code text in search
- optionally include image captions and alt text

Do not search binary attachments directly in the first version.

## 10. Sync Model

### 10.1 Sync Unit

The note should remain the primary sync unit initially.

Do not start with block-level sync merge logic.

Recommended sync payload:
- note metadata
- `document_json`
- attachment references
- attachment metadata

Attachment files sync separately from note metadata payloads.

### 10.2 Conflict Strategy

The current conflict strategy should remain conservative:
- if both sides changed and safe reconciliation is unclear, preserve both versions
- duplicate note over silent content loss

Initially, conflict handling should remain note-level, not block-level.

Why:
- simpler
- safer
- consistent with current project values

Later, block-aware diffing may be explored, but only after the editor is stable.

### 10.3 Hashing

`content_hash` should evolve to reflect:
- canonical `document_json`
- and potentially attachment references in a stable normalized form

Do not hash transient UI state.

## 11. Remote Representation

Remote note payload should evolve from plain text content to structured document payload.

Suggested remote note JSON:

```json
{
  "id": "note_uuid",
  "title": "Example",
  "document": {
    "version": 1,
    "blocks": []
  },
  "attachments": [
    {
      "id": "att_1",
      "mime_type": "image/png",
      "sha256": "..."
    }
  ],
  "created_at": 1710000000,
  "updated_at": 1710001234,
  "deleted_at": null,
  "device_id": "device_uuid",
  "content_hash": "sha256..."
}
```

Attachment binaries should remain separate remote files.

## 12. AI Architecture

### 12.1 Core Rule

AI output must be derived unless the user explicitly accepts it.

AI must not silently rewrite canonical note content.

### 12.2 AI Use Cases

Reasonable future features:
- summarize note
- rewrite selected block
- extract tasks
- generate titles
- answer questions over notes
- semantic search

### 12.3 AI Storage

Add separate tables for AI artifacts rather than embedding AI output into canonical note content by default.

Possible tables:
- `ai_artifacts`
- `ai_suggestions`
- `ai_embeddings`

Suggested `ai_artifacts` fields:
- `id`
- `note_id`
- `block_id` nullable
- `artifact_type`
- `model`
- `content_json`
- `created_at`
- `updated_at`

Suggested `ai_suggestions` fields:
- `id`
- `note_id`
- `target_block_id`
- `suggestion_type`
- `original_snapshot`
- `proposed_snapshot`
- `status`

### 12.4 AI Safety Rules

Rules:
- AI features are opt-in
- AI writes should go through explicit user acceptance
- AI artifacts should be recoverable or removable
- AI should not weaken sync correctness
- embeddings and derived indexes should be rebuildable

## 13. Migrations

### 13.1 Migration Strategy

This architecture requires deliberate migration.

Recommended migration sequence:

1. Add `document_json` to notes.
2. Add derived cache columns if needed.
3. Add attachments table.
4. Add migration code that converts existing text notes into a block document.

### 13.2 Legacy Text Conversion

Existing notes can be migrated into a simple document:
- one text note becomes one or more blocks derived from existing markdown/plain text

Safe initial migration:
- store the legacy body as a single `paragraph` or simple parsed blocks
- preserve exact user content where parsing is uncertain

Do not attempt over-aggressive markdown interpretation during migration.

### 13.3 Rollback Safety

Migration must be testable and reviewable.

Required:
- migration tests
- golden examples for plain text, markdown, and old snippet/fence content
- no destructive transform without recoverability

## 14. Implementation Phases

### Phase 1: Data Foundation

- add `document_json`
- add derived text cache fields if needed
- add attachments table
- add serialization model and tests
- migrate existing notes to a minimal block document

### Phase 2: Hybrid Block Editor

- implement paragraph and heading blocks
- render block list editor
- keep autosave local-first
- support basic split/merge behavior

### Phase 3: Code Blocks

- implement code block widget
- add always-visible copy button
- add slash command for `/code`
- add language label support

### Phase 4: Images

- implement attachment import/paste pipeline
- add image block widget
- add inline rendering in the editor
- add slash command for `/image`

### Phase 5: Search and Preview Rebuild

- rebuild preview generation from block documents
- rebuild title derivation from block documents
- rebuild search cache generation

### Phase 6: AI Foundation

- add AI artifact tables
- add selected-block or note-level suggestion flows
- keep AI derived and opt-in

## 15. Testing Requirements

Priority automated coverage:
- document serialization/deserialization
- migration tests from old text notes to document JSON
- block editor split/merge behavior
- code block copy behavior
- image attachment lifecycle
- preview generation from block documents
- title derivation from block documents
- sync round-trip with attachments
- conflict preservation with structured notes
- AI suggestion acceptance/rejection flows later

Manual QA priority:
- desktop and Android text input behavior
- paste image behavior
- code block copy UX
- slash command UX
- autosave under rapid edits
- crash/restart recovery with attachments

## 16. Risks

Main risks:
- text editing UX regressions
- platform-specific IME issues
- migration mistakes
- attachment sync complexity
- overcomplicating the first version of the block editor

Mitigations:
- phase rollout
- keep sync note-level first
- keep block types small at first
- add migration harness coverage early
- prefer safe fallback parsing over clever conversions

## 17. Recommended Decision

If Proper Notes is expected to support:
- modern code blocks
- pasted images visible inline
- slash commands
- AI features

then the correct direction is:
- keep the current local-first/sync architecture
- redesign the note body around a structured block document model
- treat attachments and AI as adjacent first-class systems
- keep all derived or assistive features downstream of canonical local data

This is a meaningful editor architecture change, but it is the right foundation for the product direction.
