# QA Checklist

This checklist remains the manual release gate for Proper Notes.

## Current Status

Current documented QA state:
- the original `v0.1.0-rc1` release-candidate gate was passed manually
- the current codebase has moved beyond that tag with folder/workspace/editor changes
- the next full manual pass should include the newer folder flows and the future code snippet mechanism when it lands

Use this checklist on:
- Linux release build
- Android release build

Use at least two real environments:
- one Linux machine
- one Android device

## 1. Install And Startup

- [X] Linux app launches successfully from the built binary.
- [X] Linux launcher entry opens the current build correctly.
- [X] Android APK installs over an existing install without losing notes.
- [X] Existing local notes still appear after app restart on both platforms.
- [X] App can open without network access.

## 2. Account And Auth

- [X] Linux sign-in succeeds with the configured desktop OAuth client.
- [X] Android sign-in succeeds with the configured Google Sign-In setup.
- [X] Reopen the app on Linux and confirm the previously signed-in account still appears.
- [X] Reopen the app on Android and confirm the previously signed-in account still appears.
- [X] Sync does not ask to sign in again when an existing session is already valid.
- [X] Sign out removes visible account state on both platforms.
- [X] Sign in again after sign-out and confirm sync still works.

## 3. Local Notes And Workspace

- [X] Create a note on Linux.
- [X] Create a note on Android.
- [X] Edit note title and body on Linux.
- [X] Edit note title and body on Android.
- [X] Delete a note locally on Linux.
- [X] Delete a note locally on Android.
- [X] Restore a deleted note locally on Linux.
- [X] Restore a deleted note locally on Android.
- [X] Search returns expected results for active notes.
- [X] Deleted notes do not appear in the active notes list.
- [ ] Create, rename, move, and delete folders on Linux and Android.
- [ ] Confirm note move and drag-and-drop flows keep folder state and selection coherent.
- [ ] Confirm the desktop sidebar, trash entry, and sync indicators behave correctly after folder operations.

## 4. Cross-Device Sync

- [X] Create a note on Android, sync Android, sync Linux, and verify the note appears correctly on Linux.
- [X] Create a note on Linux, sync Linux, sync Android, and verify the note appears correctly on Android.
- [X] Edit an Android-created note on Linux, sync Linux, sync Android, and verify the changes appear on Android.
- [X] Edit a Linux-created note on Android, sync Android, sync Linux, and verify the changes appear on Linux.
- [X] Delete a note on Android, sync Android, sync Linux, and verify the note moves to deleted state on Linux.
- [X] Delete a note on Linux, sync Linux, sync Android, and verify the note moves to deleted state on Android.
- [X] Restore a deleted note on Android, sync Android, sync Linux, and verify the note becomes active again on Linux.
- [X] Restore a deleted note on Linux, sync Linux, sync Android, and verify the note becomes active again on Android.
- [ ] Move a note to another folder on one device, sync both devices, and verify folder placement stays correct.
- [ ] Rename a folder on one device, sync both devices, and verify nested note paths update correctly.

## 5. No-Op Sync Behavior

- [X] Run sync twice in a row on Linux with no changes and confirm the second sync completes quickly.
- [X] Run sync twice in a row on Android with no changes and confirm the second sync completes quickly.
- [X] Confirm no repeated upload/download loop occurs during no-op sync.
- [X] Confirm Linux no-op sync does not get stuck in a loop.

## 6. Conflict Safety

- [X] Start from a synced note on both devices.
- [X] Turn off network on one device or avoid syncing it.
- [X] Edit the same note differently on Linux and Android.
- [X] Sync one device, then sync the other.
- [X] Confirm the app preserves both versions instead of overwriting silently.
- [X] Confirm conflict state is visible and understandable in the UI.

## 7. Stale Device Scenarios

- [X] Edit notes on Linux while Android stays offline.
- [X] Make a different edit on Android before syncing.
- [X] Bring Android back online and sync both devices.
- [X] Confirm no data is silently lost.
- [X] Delete a note on one device while the other device remains offline.
- [X] Bring the stale device online and sync both devices.
- [X] Confirm the delete does not silently resurrect or destroy newer content incorrectly.

## 8. Restart And Persistence

- [X] Sync both devices successfully.
- [X] Close and reopen Linux, then sync again without making changes.
- [X] Close and reopen Android, then sync again without making changes.
- [X] Confirm note lists, deleted notes, folder state, and account state persist across restart.

## 9. Feature-Specific Next Gate

Run these once the new code snippet mechanism from `PLAN.MD` is implemented:
- [ ] Insert a snippet on Linux and Android.
- [ ] Paste indented code and confirm whitespace is preserved exactly.
- [ ] Confirm snippet preview never interprets snippet body as markdown.
- [ ] Confirm copying a snippet copies only the inner code body if a copy action exists.
- [ ] Sync a note containing snippets between Linux and Android and confirm round-trip preservation.

## 10. Release Build Checks

- [X] Linux release build behaves the same as Linux debug build for sign-in and sync.
- [X] Android release build behaves the same as Android debug build for sign-in and sync.
- [X] Updating Android with `adb install -r` preserves local note data.
- [X] Updating Linux release and reinstalling the launcher still opens the latest build.

## 11. Known-Issue Capture

For every reproducible bug found during QA, record:
- platform
- build type
- exact steps
- expected result
- actual result
- sync summary text shown by the app

Do not fix bugs based only on vague recollection. Reproduce first.

## Exit Criteria For The Next Release Build

The build is acceptable when:
- local create/edit/delete/restore remains reliable
- folder operations remain reliable locally and across sync
- no-op sync is fast and stable on both Linux and Android
- conflict preservation works without silent overwrite
- restart does not lose notes, folders, or account state
- any shipped code snippet workflow preserves code content exactly
- no unresolved reproducible data-loss bug remains
