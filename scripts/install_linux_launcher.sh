#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_PATH="$REPO_ROOT/build/linux/x64/release/bundle/proper_notes"
DESKTOP_TEMPLATE="$REPO_ROOT/packaging/linux/proper-notes.desktop"
APPLICATIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP_FILE="$APPLICATIONS_DIR/proper-notes.desktop"

if [[ ! -x "$BUNDLE_PATH" ]]; then
  cat >&2 <<EOF
Linux release bundle not found at:
  $BUNDLE_PATH

Build it first:
  cd "$REPO_ROOT"
  flutter build linux --release \\
    --dart-define=GOOGLE_DESKTOP_CLIENT_ID=YOUR_DESKTOP_CLIENT_ID.apps.googleusercontent.com \\
    --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=YOUR_DESKTOP_CLIENT_SECRET
EOF
  exit 1
fi

mkdir -p "$APPLICATIONS_DIR"
sed "s|__EXEC_PATH__|$BUNDLE_PATH|g" "$DESKTOP_TEMPLATE" > "$DESKTOP_FILE"
chmod +x "$DESKTOP_FILE"

cat <<EOF
Installed launcher:
  $DESKTOP_FILE

You can now open Proper Notes from your desktop app launcher/menu.
EOF
