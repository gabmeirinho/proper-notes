# NEXT_STEPS.md

This file is the short handoff for the next agent or chat session.

## Current State

Proper Notes currently has:
- working local-first notes on Linux and Android
- working manual sync using Google Drive `appDataFolder`
- working cross-device create, edit, delete, restore, and conflict-copy behavior
- a completed full manual QA pass on Linux and Android release builds

The project is past the main sync-debugging phase.

## Immediate Next Steps

The next work should be release-oriented, not architectural:

1. Choose the first release-candidate version.
   Suggested example:
   - `v0.1.0-rc1`

2. Build final release artifacts from the exact commit to be tagged.
   - Linux release build
   - Android release APK

3. Tag the exact tested commit.
   - the tagged commit should match the binaries that passed QA

4. Write short release notes.
   Include:
   - local-first notes
   - Linux and Android support
   - manual Google Drive sync
   - conflict-copy preservation
   - manual sync only, background sync deferred

5. Only after that, continue with smaller follow-up work:
   - more automated tests for restore/stale-device/migration coverage
   - small sync/account UX polish
   - packaging and release automation improvements

## What Not To Do Next

Do not start with:
- background sync
- WorkManager integration
- a major UI redesign
- a new auth architecture
- large sync refactors without a newly reproducible bug

Those are explicitly later unless a real regression forces them.

## Release Gate Status

The current QA gate has already been passed manually on Linux and Android release builds.

Before changing sync logic again, prefer:
- reproducing a new bug with exact steps
- recording sync summary text from both devices
- patching only the specific failing case

## Supporting Docs

Read these first:
- `README.md`
- `PLAN.MD`
- `QA_CHECKLIST.md`
- `DECISIONS.md`
