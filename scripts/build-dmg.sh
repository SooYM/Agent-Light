#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/outputs/Token Signal.app"
BACKGROUND="$ROOT/Resources/DMGBackground.png"
OUTPUT="$ROOT/outputs/Token-Signal.dmg"
VOLUME="Token Signal"
TEMP_ROOT="$(mktemp -d "${TMPDIR%/}/agent-light-dmg.XXXXXX")"
SOURCE="$TEMP_ROOT/source"
RW_DMG="$TEMP_ROOT/Token-Signal-rw.dmg"
DEVICE=""

cleanup() {
    if [[ -n "$DEVICE" ]]; then
        hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true
    fi
    if [[ "$TEMP_ROOT" == "${TMPDIR%/}"/agent-light-dmg.* ]]; then
        rm -rf "$TEMP_ROOT"
    fi
}
trap cleanup EXIT INT TERM

[[ ! -e "/Volumes/$VOLUME" ]] || {
    print -u2 "Refusing to build while /Volumes/$VOLUME is mounted"
    exit 1
}

zsh "$ROOT/scripts/build-app.sh" >/dev/null
mkdir -p "$SOURCE/.background"
ditto "$APP" "$SOURCE/Token Signal.app"
ln -s /Applications "$SOURCE/Applications"
cp "$BACKGROUND" "$SOURCE/.background/DMGBackground.png"
chflags hidden "$SOURCE/.background"

hdiutil create \
    -volname "$VOLUME" \
    -srcfolder "$SOURCE" \
    -format UDRW \
    -ov "$RW_DMG" >/dev/null

DEVICE="$(hdiutil attach \
    -readwrite \
    -noverify \
    -noautoopen \
    "$RW_DMG" | awk '/^\/dev\// { print $1; exit }')"
[[ -n "$DEVICE" ]] || { print -u2 "Could not determine mounted DMG device"; exit 1; }
sleep 1

osascript - "$VOLUME" <<'APPLESCRIPT'
on run argv
    set volumeName to item 1 of argv
    tell application "Finder"
        tell disk volumeName
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {100, 100, 820, 580}

            set viewOptions to icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 128
            set text size of viewOptions to 14
            set background picture of viewOptions to file ".background:DMGBackground.png"

            set position of item "Token Signal.app" of container window to {165, 205}
            set position of item "Applications" of container window to {555, 205}
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT

sync
for attempt in 1 2 3; do
    if hdiutil detach "$DEVICE" >/dev/null; then
        DEVICE=""
        break
    fi
    sleep 1
done
[[ -z "$DEVICE" ]] || { print -u2 "Could not detach DMG safely"; exit 1; }

hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "$TEMP_ROOT/Token-Signal.dmg" >/dev/null
mv -f "$TEMP_ROOT/Token-Signal.dmg" "$OUTPUT"
hdiutil verify "$OUTPUT" >/dev/null

print "$OUTPUT"
