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
# Every source file, in one place. Add a new .swift file here and nowhere else.
SOURCES=("$DIR"/{Companion,Live,Wiki,Clips,Keychain,Conversation,CompanionConversation,CompanionInterface,FridayOrb,FridayCorner,StockData,VentureData,StripeData,MeetingData,MeetingRoom,ClipMath,ClipEditor,StreamData,StreamManager,SecretFile,FeedData,FridayFeed,ChatData,ChatHelper,AudioRoute,HandsData,ScreenSnap,VodData,VodClips,FridayHands,Hub}.swift)
# The compiler's warnings (dozens of harmless "deprecated" notes) are hidden. A real error is shown on its own,
# loudly, because a failed build leaves the OLD app installed and it used to look like nothing had happened.
LOG="$TMP/build.log"
if ! xcrun swiftc -O -parse-as-library -target "arm64-apple-macos$MACOS.0" "${SOURCES[@]}" -o "$TMP/$EXE" >"$LOG" 2>&1; then
 echo ""
 echo "BUILD FAILED. The app was NOT updated: the old version is still installed."
 echo "Copy everything between the two lines below and paste it to Claude:"
 echo "------------------------------------------------------------"
 grep -A4 "error:" "$LOG" | head -60
 echo "------------------------------------------------------------"
 exit 1
fi
echo "Compiled OK ($(grep -c 'warning:' "$LOG" || true) harmless warnings hidden)."

pkill -x "$EXE" 2>/dev/null || true
# The backup is a zip, not a second .app: a second copy with the same app ID confused macOS,
# which listed "GameCompanion-backup" in Screen Recording instead of the real app.
rm -rf "$PROJECT/outputs/GameCompanion-backup.app" "$PROJECT/outputs/GameCompanion-backup.zip"
ditto -c -k --keepParent "$APP" "$PROJECT/outputs/GameCompanion-backup.zip"
cp "$TMP/$EXE" "$APP/Contents/MacOS/$EXE"
cp "${SOURCES[@]}" "$PROJECT/outputs/"

# Sign with the stable "GameCompanion Signing" certificate when it exists, so macOS keeps the
# Screen Recording permission and the Keychain approval across rebuilds. An ad hoc signature
# changes on every build, and macOS then treats the app as new.
SIGN_ID="GameCompanion Signing"
if security find-certificate -c "$SIGN_ID" >/dev/null 2>&1 && codesign --force --sign "$SIGN_ID" --preserve-metadata=entitlements,flags,runtime "$APP"; then
 echo "Signed with the stable certificate, so permissions should stick from now on."
else
 ID=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)
 codesign --force --sign "${ID:--}" --preserve-metadata=entitlements,requirements,flags,runtime "$APP"
 echo "No \"$SIGN_ID\" certificate yet, so it's signed ad hoc and permissions will reset."
fi

echo "Done. Open Game Companion from the Desktop icon, then redo the screen permission."
echo "(If anything is wrong, the old app is saved as outputs/GameCompanion-backup.zip)"
