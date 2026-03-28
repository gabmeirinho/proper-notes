# QA Checklist

This checklist is the release gate for Proper Notes v1.

Goal:
- verify local-first note behavior
- verify Linux and Android sync behavior
- catch data-loss regressions before release

Test on:
- Linux release build
- Android release build

Use at least two real devices/environments:
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

## 3. Local Notes

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

## 4. Cross-Device Sync

### Create

- [X] Create a note on Android, sync Android, sync Linux, and verify the note appears correctly on Linux.
- [X] Create a note on Linux, sync Linux, sync Android, and verify the note appears correctly on Android.

### Edit

- [X] Edit an Android-created note on Linux, sync Linux, sync Android, and verify the changes appear on Android.
- [X] Edit a Linux-created note on Android, sync Android, sync Linux, and verify the changes appear on Linux.

### Delete

- [X] Delete a note on Android, sync Android, sync Linux, and verify the note moves to deleted state on Linux.
- [X] Delete a note on Linux, sync Linux, sync Android, and verify the note moves to deleted state on Android.

### Restore

- [X] Restore a deleted note on Android, sync Android, sync Linux, and verify the note becomes active again on Linux.
- [X] Restore a deleted note on Linux, sync Linux, sync Android, and verify the note becomes active again on Android.

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
- [X] Confirm note lists, deleted notes, and account state persist across restart.

## 9. Release Build Checks

- [X] Linux release build behaves the same as Linux debug build for sign-in and sync.
- [X] Android release build behaves the same as Android debug build for sign-in and sync.
- [X] Updating Android with `adb install -r` preserves local note data.
- [X] Updating Linux release and reinstalling the launcher still opens the latest build.

## 10. Known-Issue Capture

For every reproducible bug found during QA, record:
- platform
- build type
- exact steps
- expected result
- actual result
- sync summary text shown by the app

Do not fix bugs based only on vague recollection. Reproduce first.

## Exit Criteria For First v1 Build

The build is acceptable for a first v1 release candidate when:
- all create/edit/delete/restore sync paths work in both directions
- no-op sync is fast and stable on both Linux and Android
- conflict preservation works without silent overwrite
- restart does not lose notes or account state
- no unresolved reproducible data-loss bug remains
