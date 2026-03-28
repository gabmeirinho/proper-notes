# Proper Notes

Proper Notes is a local-first note-taking app for Linux desktop and Android.

Current stack:
- Flutter
- Dart 3.x
- Drift + SQLite
- Google Drive `appDataFolder` sync

Current capabilities:
- markdown/plain-text notes
- local create, edit, delete, restore
- local search
- Google sign-in on Linux and Android
- manual sync with conflict preservation
- cross-device create, edit, delete, restore, and conflict-copy sync between Linux and Android
- Linux launcher install flow
- Android release APK install/update workflow

## Current Status

What is already working:
- local-first note editing
- deleted-notes and restore flow
- repeated no-op sync without the earlier upload loop
- restore propagation across devices
- delete-vs-edit conflict preservation with conflict copies
- release-build validation on Linux and Android
- full manual QA checklist pass on Linux and Android release builds

What is still worth doing before calling v1 complete:
- add more automated tests for stale-device, restore, and migration scenarios
- tighten some small sync/account UX details
- decide the exact first release-candidate version/tag and release notes

Immediate handoff for the next chat/agent:
- use `NEXT_STEPS.md`

## Identity

- App name: `Proper Notes`
- Android package id: `com.gabriel.propernotes`
- Linux GTK application id: `com.gabriel.propernotes`

If you previously created Google OAuth clients for `com.example.proper_notes`, create new Android OAuth credentials for `com.gabriel.propernotes`.

## Google Cloud Setup

Create or select a Google Cloud project, then:

1. Enable `Google Drive API`.
2. Configure the OAuth consent screen.
3. Keep the app in `Testing`.
4. Add your Google account as a test user.
5. Create these OAuth clients:
   - Desktop app client
   - Android client for `com.gabriel.propernotes`
   - Web application client

### Android OAuth Client

Use:
- Package name: `com.gabriel.propernotes`
- SHA-1: from `./gradlew signingReport`

To get the debug SHA-1:

```bash
cd android
./gradlew signingReport
```

For release builds, Google sign-in also needs the SHA-1 of your release keystore.
After creating your release keystore, add that release SHA-1 to the Android OAuth client too.

### Linux/Desktop OAuth Client

Use the desktop client ID and secret as Dart defines when running or building the Linux app.

### Web OAuth Client

Use the Web client ID as `GOOGLE_ANDROID_SERVER_CLIENT_ID` on Android.

## Local Environment

Required:
- Flutter SDK
- Dart SDK
- Android Studio + Android SDK for Android builds
- JDK 17 for Android/Gradle

Helpful Android setup:

```bash
flutter config --android-sdk "$HOME/Android/Sdk"
flutter doctor --android-licenses
flutter doctor
```

If Gradle/JDK selection is unstable, set:

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
```

## Run

Linux:

```bash
cd /path/to/proper-notes
flutter run -d linux \
  --dart-define=GOOGLE_DESKTOP_CLIENT_ID=YOUR_DESKTOP_CLIENT_ID.apps.googleusercontent.com \
  --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=YOUR_DESKTOP_CLIENT_SECRET
```

Android:

```bash
cd /path/to/proper-notes
flutter run -d YOUR_ANDROID_DEVICE_ID \
  --dart-define=GOOGLE_ANDROID_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

## Build

Linux release:

```bash
cd /path/to/proper-notes
flutter build linux --release \
  --dart-define=GOOGLE_DESKTOP_CLIENT_ID=YOUR_DESKTOP_CLIENT_ID.apps.googleusercontent.com \
  --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=YOUR_DESKTOP_CLIENT_SECRET
./build/linux/x64/release/bundle/proper_notes
```

Linux launcher install:

```bash
cd /path/to/proper-notes
./scripts/install_linux_launcher.sh
```

This installs a user-local launcher in:

```text
~/.local/share/applications/proper-notes.desktop
```

Re-run the script after rebuilding the Linux release if the bundle path changes.

Android release APK:

```bash
cd /path/to/proper-notes
flutter build apk --release \
  --dart-define=GOOGLE_ANDROID_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

### Android release signing

Create a release keystore:

```bash
keytool -genkeypair -v \
  -keystore "$HOME/.keystores/proper-notes-upload.jks" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias upload
```

Then create `android/key.properties` from `android/key.properties.example`:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=/absolute/path/to/your-keystore.jks
```

`android/key.properties` is gitignored on purpose.

After that, build the release APK:

```bash
cd /path/to/proper-notes
flutter build apk --release \
  --dart-define=GOOGLE_ANDROID_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

To get the release SHA-1 for Google Cloud:

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"

cd android
./gradlew signingReport
```

Then add the `release` SHA-1 fingerprint to the Android OAuth client in Google Cloud.

## Cross-Device Test Checklist

Run these before trusting the app with important notes:

1. Create on Android, sync to Linux.
2. Create on Linux, sync to Android.
3. Edit on one device, sync to the other.
4. Delete and restore across both devices.
5. Create a deliberate conflict and verify both versions are preserved.
6. Sign out, sign back in, and verify sync still works.

For the full release gate, use `QA_CHECKLIST.md`.

Current QA status:
- latest full manual QA pass completed successfully on Linux and Android release builds

## Current Caveats

- This is still an early-stage app, not a polished production release.
- Sync is manual-first by design.
- Background sync is intentionally deferred.
- Keep backups for important notes until the project has gone through a first tagged release candidate and broader real-world usage.
