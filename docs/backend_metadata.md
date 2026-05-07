# Backend Metadata

Proper Notes keeps local SQLite state as the source of truth. Remote metadata is
only cache state used to make WebDAV sync efficient and recoverable.

## App Metadata

`device_id` is the stable local device identifier. It must be preserved across
schema migrations because sync and conflict records use it for debugging and
provenance.

`remote_sync_cursor` is the canonical sync cursor. For WebDAV this cursor is a
local fingerprint of the remote notes and tombstones listings, not a server-owned
identity.

`remote_collection_tag` is an optional WebDAV collection hint. Sync correctness
must not depend on it because not every WebDAV server exposes the same
properties.

`remote_format_version` records the Proper Notes remote layout version when it
is known.

`remote_base_url`, `remote_username`, and `account_label` are non-secret account
metadata for display or debugging. WebDAV passwords are stored through secure
storage, not SQLite.

`last_full_sync_at` and `last_successful_sync_at` are observability fields. They
must not be used to decide conflict correctness.

## Legacy Fields

`drive_sync_token` and `account_email` are Google-era fields kept in the schema
only so older local databases can be upgraded safely. Schema version 6 promotes
an existing `drive_sync_token` into `remote_sync_cursor` when no canonical cursor
exists, then clears both legacy fields.

Runtime sync code must read and write `remote_sync_cursor` only. Legacy Drive
metadata is not an active sync source.
