#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_PATH="$REPO_ROOT/build/linux/x64/release/bundle/proper_notes"
DESKTOP_TEMPLATE="$REPO_ROOT/packaging/linux/proper-notes.desktop"
ICON_TEMPLATE="$REPO_ROOT/packaging/linux/proper-notes.png"
APPLICATIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/256x256/apps"
DESKTOP_FILE="$APPLICATIONS_DIR/com.gabriel.propernotes.desktop"
ICON_FILE="$ICONS_DIR/com.gabriel.propernotes.png"

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
mkdir -p "$ICONS_DIR"
rm -f "$APPLICATIONS_DIR/proper-notes.desktop"
cp "$ICON_TEMPLATE" "$ICON_FILE"
sed \
  -e "s|__EXEC_PATH__|$BUNDLE_PATH|g" \
  "$DESKTOP_TEMPLATE" > "$DESKTOP_FILE"
chmod +x "$DESKTOP_FILE"

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor" >/dev/null 2>&1 || true
fi

cat <<EOF
Installed launcher:
  $DESKTOP_FILE
Installed icon:
  $ICON_FILE

You can now open Proper Notes from your desktop app launcher/menu.
EOF
