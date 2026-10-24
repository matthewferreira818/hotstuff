#!/bin/zsh
# Rebuilds Friday (the app was called Game Companion) from the Swift files next to this script, with no Codex needed.
# It compiles first and only touches the app if the compile succeeds; the old app is kept as a backup.
set -e
PROJECT=~/Documents/Codex/2026-10-04/create-a-separate-free-local-ai
APP="$PROJECT/outputs/GameCompanion.app"
DIR="${0:A:h}"
EXE=$(defaults read "$APP/Contents/Info" CFBundleExecutable)
MACOS=$(sw_vers -productVersion | cut -d. -f1)
TMP=$(mktemp -d)

echo "Building The Helm (takes a minute)…"
# Every source file, in one place. Add a new .swift file here and nowhere else.
SOURCES=("$DIR"/{Companion,Live,Wiki,Clips,Keychain,Conversation,CompanionConversation,CompanionInterface,FridayOrb,FridayCorner,StockData,VentureData,StripeData,MeetingData,SpeechData,ThreadData,MeetingVoice,MeetingRoom,ClipMath,ClipEditor,StreamData,StreamManager,SecretFile,FeedData,FridayFeed,ChatData,ChatHelper,AudioRoute,HandsData,ScreenSnap,VodData,VodClips,AutopilotData,ClipAutopilot,VoiceOverData,VoiceOver,WebData,ObsData,ObsBridge,VideoLabData,VideoLab,HelperData,Helper,FridayHands,Hub,HubTheme,HubShell,HubHome,HubStocks,HubVentures,HubLaunchpad,HubGame,HubAccounts,HubHelpers}.swift)
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

# Branding (Matthew, 2026-10-14: "name it Friday, and surprise me with the icon"; renamed 2026-10-24: the app is now called The Helm, and Friday is the voice inside it). The icon is still the one drawn in icon/.
# Only the display name and the icon change. The app ID, the file name and the saved data stay exactly as they were, so macOS keeps its
# permissions and nothing is lost. This runs before signing, so the signature covers it.
PLIST="$APP/Contents/Info.plist"
setkey() { /usr/libexec/PlistBuddy -c "Set :$1 \"$2\"" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :$1 string \"$2\"" "$PLIST"; }
setkey CFBundleName "The Helm" || true
setkey CFBundleDisplayName "The Helm" || true
if [ -f "$DIR/icon/Friday-1024.png" ]; then
 SET="$TMP/Friday.iconset"
 mkdir -p "$SET"
 for s in 16 32 128 256 512; do
  sips -z $s $s "$DIR/icon/Friday-1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null || true
  sips -z $((s * 2)) $((s * 2)) "$DIR/icon/Friday-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null || true
 done
 if iconutil -c icns "$SET" -o "$TMP/Friday.icns" 2>/dev/null; then
  mkdir -p "$APP/Contents/Resources"
  cp "$TMP/Friday.icns" "$APP/Contents/Resources/Friday.icns"
  setkey CFBundleIconFile Friday || true
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "$PLIST" 2>/dev/null || true
  echo "Friday's new icon is in."
 else
  echo "(Couldn't make the icon file; the name was still changed.)"
 fi
fi

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

touch "$APP"
killall Dock 2>/dev/null || true   # the Dock restarts at once; it picks up the new name and icon
echo "Done. Open The Helm from the Desktop icon, then redo the screen permission."
echo "(If anything is wrong, the old app is saved as outputs/GameCompanion-backup.zip)"
