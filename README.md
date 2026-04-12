# Proper Notes

Proper Notes is a local-first note-taking app built with Flutter.

The project is aimed at Linux desktop and Android, with local persistence as the primary source of truth and sync handled separately from the UI.

## Features

* **Local-First:** Your local SQLite database remains the source of truth, so you can keep working entirely offline.
* **Organization:** Nested folders, drag-and-drop support, local search, and trash/restore functionality.
* **Editor:** A clean editing surface with inline markdown previews for headings, lists, quotes, and attachments.
* **Your Data, Your Storage:** WebDAV-based manual sync lets you control your own storage while preserving a simple, conflict-safe flow between devices.

---

## Sync Configuration (WebDAV)

Proper Notes uses WebDAV for manual synchronization. A typical setup uses Nextcloud or another WebDAV-compatible server, letting you keep your notes on storage you control.

To configure sync within the app, you will need:
* The WebDAV server URL
* Your username
* Your password (or, preferably for Nextcloud, an app-specific password)

**Example Nextcloud Configuration:**
```text
URL: https://cloud.example.com/remote.php/dav/files/username/ProperNotes/
Username: username
Password: your-nextcloud-app-password
```

---

## Obsidian Import

If you are migrating from Obsidian, you can easily import `.md` files from an existing vault using the included CLI script. 

**Dry run preview:**
```bash
dart run scripts/import_obsidian.dart --vault ~/Documents/MyVault
```

**Apply the import:**
```bash
dart run scripts/import_obsidian.dart \
  --vault ~/Documents/MyVault \
  --folder-prefix Imported/Obsidian \
  --apply
```
> **Note:** Conflicting folder/title pairs are imported as extra local notes rather than overwritten to ensure no data loss during the migration.

---

## Tech Stack & Architecture

* **UI:** Flutter and Dart
* **Storage:** Drift with SQLite
* **Sync:** WebDAV-based sync infrastructure
* **Security:** Secure storage for credentials

### Project Structure
* `lib/features/`: App features such as notes, authentication, and sync.
* `lib/infrastructure/`: Database, repository, and service implementations.
* `lib/core/`: Shared utilities, errors, and common services.
* `test/`: Unit and widget tests.

---

## Development

**Prerequisites:**
* Flutter SDK
* Dart SDK
* Android Studio & Android SDK (for Android builds)
* JDK 17 (for Android/Gradle)

**Common Commands:**
```bash
flutter pub get
flutter test
flutter run -d linux
```

To build a Linux release and install the user-local launcher (`~/.local/share/applications/proper-notes.desktop`):
```bash
flutter build linux --release
./scripts/install_linux_launcher.sh
```

---

## Status & Caveats

This repository is under active development. The architecture is currently being shaped around a reliable, offline-first notes workflow.

* **Pre-Release:** This is still pre-`0.1.0`.
* **Sync:** Sync is manual/foreground first by design. Background sync is intentionally deferred for now.
* **Data Safety:** Please keep backups for important notes until the project has gone through a stable release and more real-world usage.
