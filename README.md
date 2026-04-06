# Proper Notes

Proper Notes is a local-first note-taking app for Linux desktop and Android.

## Current Snapshot

Current implementation state as of April 2026:
- Flutter + Dart 3.x
- Drift over SQLite as the local source of truth
- schema version `2` with logical folders stored locally
- Google Drive `appDataFolder` manual sync with delta-token support
- Linux and Android sign-in flows are implemented
- full `flutter test` currently passes in this workspace

Current user-facing capabilities:
- create, edit, delete, restore, and search notes locally
- local autosave with debounce plus lifecycle/close flushing
- nested folders with rename, move, drag-and-drop, and subtree-aware delete flows
- desktop workspace with a collapsible sidebar, trash in the workspace, and an embedded editor
- lighter mobile layout with folder context moved into the app bar
- per-note sync-state indicators and dismissible sync notices
- cross-device create, edit, delete, restore, and conflict-copy preservation
- Linux launcher install flow and Android release APK workflow

## Editor And Markdown State

The note body is still stored as one plain text/markdown field.

Current editor behavior:
- one text editor remains the canonical editing surface
- inactive lines render headings, bullets, and quotes in a friendlier way
- the editor still has fence-based code insertion and inactive-line fenced-code styling

Current preview behavior:
- note list previews render headings, paragraphs, lists, quotes, dividers, bold, italic, and inline code
- dedicated fenced code block preview support was removed
- triple backticks now fall through as normal text in the preview layer

Important current gap:
- the app does not yet have a first-class, copy-friendly code snippet mechanism
- the planned replacement for fenced code blocks is documented in `PLAN.MD`

## Current Priorities

The most important near-term product work is:
- replace fence-based code insertion with a first-class code snippet workflow
- persist desktop sidebar collapse and expanded-folder state locally
- add more stale-device, migration, and broader integration coverage
- tighten release packaging and release discipline for the first stable build

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

## Obsidian Import

There is no in-app vault importer yet, but you can import `.md` files from an
Obsidian vault with the CLI script below.

Dry run preview:

```bash
cd /path/to/proper-notes
dart run scripts/import_obsidian.dart \
  --vault ~/Documents/MyVault
```

Apply the import:

```bash
cd /path/to/proper-notes
dart run scripts/import_obsidian.dart \
  --vault ~/Documents/MyVault \
  --folder-prefix Imported/Obsidian \
  --apply
```

Notes:
- the script skips hidden paths such as `.obsidian/` by default
- exact duplicates already in Proper Notes are skipped
- conflicting folder/title pairs are imported as extra local notes rather than overwritten
- by default the script targets `~/.local/share/com.gabriel.propernotes/proper_notes.sqlite`
- use `--db /absolute/path/to/proper_notes.sqlite` if your database lives elsewhere

Android release APK:

```bash
cd /path/to/proper-notes
flutter build apk --release \
  --dart-define=GOOGLE_ANDROID_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

### Android Release Signing

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

## Verification

Current verification state:
- the full automated Flutter test suite is green in this workspace
- the last tagged release candidate is `v0.1.0-rc1`
- the current worktree has moved beyond that tag

For manual release validation and cross-device checks, use `QA_CHECKLIST.md`.

## Current Caveats

- This is still pre-`0.1.0`.
- Sync is manual/foreground first by design.
- Background sync is intentionally deferred.
- The code snippet UX is not finished yet; fence-based insertion is still present in the editor until the replacement lands.
- Keep backups for important notes until the project has gone through a stable release and more real-world usage.
