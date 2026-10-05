#!/bin/zsh
# Rebuilds Game Companion from the Swift files next to this script, with no Codex needed.
# It compiles first and only touches the app if the compile succeeds; the old app is kept as a backup.
set -e
PROJECT=~/Documents/Codex/2026-10-04/create-a-separate-free-local-ai
APP="$PROJECT/outputs/GameCompanion.app"
DIR="${0:A:h}"
EXE=$(defaults read "$APP/Contents/Info" CFBundleExecutable)
MACOS=$(sw_vers -productVersion | cut -d. -f1)
TMP=$(mktemp -d)

echo "Building Game Companion (takes a minute)…"
xcrun swiftc -O -parse-as-library -target "arm64-apple-macos$MACOS.0" "$DIR/Companion.swift" "$DIR/Live.swift" -o "$TMP/$EXE"

pkill -x "$EXE" 2>/dev/null || true
rm -rf "$PROJECT/outputs/GameCompanion-backup.app"
cp -R "$APP" "$PROJECT/outputs/GameCompanion-backup.app"
cp "$TMP/$EXE" "$APP/Contents/MacOS/$EXE"
cp "$DIR/Companion.swift" "$DIR/Live.swift" "$PROJECT/outputs/"

# Re-sign with whatever identity the app already had (ad hoc if none).
ID=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
codesign --force --sign "${ID:--}" --preserve-metadata=entitlements,requirements,flags,runtime "$APP"

echo "Done. Open Game Companion from the Desktop icon, then redo the screen permission."
echo "(If anything is wrong, the old app is saved as outputs/GameCompanion-backup.app)"
