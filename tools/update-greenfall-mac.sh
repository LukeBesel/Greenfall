#!/bin/bash
# Installs or updates Greenfall on a Mac from the newest build, with no "Open Anyway" prompt.
# macOS only blocks apps that a *browser* downloaded (it tags them with a quarantine flag);
# this script downloads with the GitHub CLI and clears the flag, so the game just opens.
#
# One-time setup:  brew install gh   (or get it from https://cli.github.com)   then:  gh auth login
# Every update:    ~/update-greenfall.sh
# Saves are kept (they live in ~/Library/Application Support, not in the app).
set -euo pipefail
REPO="LukeBesel/Greenfall"
DEST="${GREENFALL_DIR:-$HOME/Applications}"

if ! command -v gh >/dev/null 2>&1; then
  echo "The GitHub CLI isn't installed. Install it once with:  brew install gh"
  echo "(or download it from https://cli.github.com), then run:  gh auth login"
  exit 1
fi
gh auth status >/dev/null 2>&1 || gh auth login

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "Downloading the newest Greenfall..."
gh release download latest -R "$REPO" -p "Greenfall-macOS.zip" -D "$TMP"
cd "$TMP"
unzip -q Greenfall-macOS.zip
# The export can be a zip inside the zip; unpack until the .app appears.
for i in 1 2 3; do
  APP="$(find . -maxdepth 3 -name '*.app' -type d | head -1)"
  [ -n "$APP" ] && break
  INNER="$(find . -maxdepth 2 -name '*.zip' ! -name 'Greenfall-macOS.zip' | head -1)"
  [ -n "$INNER" ] && unzip -qo "$INNER" -d . || break
done
[ -n "${APP:-}" ] || { echo "Couldn't find Greenfall.app in the download."; exit 1; }

mkdir -p "$DEST"
pkill -x Greenfall 2>/dev/null || true
rm -rf "$DEST/Greenfall.app"
ditto "$APP" "$DEST/Greenfall.app"
xattr -dr com.apple.quarantine "$DEST/Greenfall.app" 2>/dev/null || true
codesign --force --deep --sign - "$DEST/Greenfall.app" >/dev/null 2>&1 || true

# Keep this updater itself current too.
gh release download latest -R "$REPO" -p "update-greenfall.sh" -O "$HOME/update-greenfall.sh" --clobber 2>/dev/null && chmod +x "$HOME/update-greenfall.sh" || true

echo "Greenfall is up to date in $DEST. Launching..."
open "$DEST/Greenfall.app"
