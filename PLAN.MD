# Proper Notes Next Steps

This file replaces the earlier migration document with the concrete next milestone for the app.

The current product already has:
- local-first notes and folders
- editor and autosave flows
- manual sync wiring
- WebDAV account setup
- a working WebDAV gateway

The main remaining risk is not feature breadth. It is trust:
- finishing the backend cutover cleanly
- proving sync safety in edge cases
- shipping a version that matches the stated v1 scope

## Current Priority

Finish the WebDAV transition and harden sync correctness before adding more product surface area.

Why this is the next step:
- the app already delivers the core offline note workflow
- WebDAV is already the active runtime direction
- Google-era code and vocabulary still remain in the repo
- sync is the safety-critical subsystem for this product

## Milestone Goal

Reach a v1-ready backend state where:
- WebDAV is the only supported sync path in the product
- Google OAuth and Google Drive are no longer required to build or run the app
- upgrade from older local databases is safe
- sync behavior is conservative and test-covered for conflict and deletion scenarios
- real Nextcloud verification is repeatable

## Step 1: Complete The WebDAV Cutover

Remove Google-specific product and infrastructure code that no longer fits v1.

Deliverables:
- remove `google_sign_in` and any unused Google-only dependencies
- remove Google auth services, token clients, config files, and Drive gateway code once migration safety is covered
- remove Google-era tests that only validate dead paths
- remove fallback behavior that treats Drive-specific state as normal runtime sync state
- update labels, comments, and naming that still describe the app as Google-backed

Guardrails:
- do not break upgrade safety for existing local databases
- do not remove fields or code paths until migration coverage exists

## Step 2: Finish Metadata Migration Cleanly

The app metadata layer still carries migration residue. Clean that up explicitly.

Deliverables:
- review whether `drive_sync_token` should be preserved only for one-time upgrade handling or removed entirely
- make `remote_sync_cursor` the canonical sync cursor field
- preserve `device_id`
- preserve enough account metadata for debuggability without storing secrets in SQLite
- document the final meaning of app metadata fields

Required tests:
- migration from a Google-era schema to the current schema
- migration preserving `device_id`
- migration behavior when legacy Drive token data exists

## Step 3: Harden WebDAV Sync Safety

Expand coverage around the cases most likely to damage trust.

Required behavior to verify:
- missing remote note file without tombstone is treated as ambiguous, not deletion
- concurrent local edit and remote delete preserves user content
- stale device returns after long offline period without silent loss
- partial failure mid-sync is recoverable on retry
- malformed `PROPFIND` responses fail explicitly
- missing ETags do not break correctness
- attachment upload and download retries remain safe
- delete and restore flows remain tombstone-first

Required tests:
- application-layer reconciliation tests
- WebDAV gateway failure-mode tests
- stale-device tests
- delete-resurrection tests
- conflict-copy preservation tests

## Step 4: Run Real Nextcloud Verification

Mock tests are necessary but not sufficient.

Create a repeatable manual verification checklist against a real Nextcloud server.

Minimum checklist:
- connect with server URL, username, and app password
- bootstrap remote folder layout
- upload a new note
- edit the same note on another device and sync both sides
- delete and restore notes across devices
- verify attachment upload and retrieval
- verify auth failure handling without corrupting local state
- verify reconnect after invalid credentials

## Step 5: Only Then Add New Features

After the cutover and hardening milestone is complete, the next product-facing priorities should be:
- polish sync status UX so users understand what happened during manual sync
- improve conflict visibility and recovery UX
- add stronger attachment handling polish
- consider background sync only after manual sync is boring and reliable

Not the next step right now:
- new backend providers
- collaboration
- rich editor expansion
- broad platform expansion beyond the current Linux and Android focus

## Definition Of Done

This milestone is complete when:
- the app builds and runs without Google dependencies
- WebDAV is the only active sync backend
- migration tests pass
- sync safety tests cover the critical edge cases
- a real Nextcloud checklist has been executed successfully
- docs describe the actual shipped architecture rather than the transition
