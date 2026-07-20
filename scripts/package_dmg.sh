#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Codex Island.app"
STAGE_DIR="$DIST_DIR/.dmg-stage"
RW_DMG="$DIST_DIR/.Codex-Island-rw.dmg"
FINAL_DMG="$DIST_DIR/Codex-Island.dmg"
ICON_FILE="$ROOT_DIR/Packaging/CodexIsland.icns"
DMG_ICON="$DIST_DIR/.CodexIsland-dmg-icon.icns"
ICON_RSRC="$DIST_DIR/.CodexIsland-icon.rsrc"
MOUNT_DIR="$(mktemp -d /tmp/codex-island-dmg.XXXXXX)"
MOUNTED=0

cleanup() {
    if (( MOUNTED )); then
        hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    fi
    rm -rf "$MOUNT_DIR" "$STAGE_DIR"
    rm -f "$RW_DMG" "$DMG_ICON" "$ICON_RSRC"
}
trap cleanup EXIT

"$ROOT_DIR/scripts/package_app.sh" >/dev/null

rm -rf "$STAGE_DIR"
rm -f "$RW_DMG" "$FINAL_DMG" "$DMG_ICON" "$ICON_RSRC"
mkdir -p "$STAGE_DIR"
ditto "$APP_DIR" "$STAGE_DIR/Codex Island.app"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
    -volname "Codex Island" \
    -srcfolder "$STAGE_DIR" \
    -fs HFS+ \
    -format UDRW \
    "$RW_DMG" >/dev/null

hdiutil attach \
    -nobrowse \
    -noautoopen \
    -mountpoint "$MOUNT_DIR" \
    "$RW_DMG" >/dev/null
MOUNTED=1

install -m 644 "$ICON_FILE" "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -a C "$MOUNT_DIR"
sync

hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNTED=0

hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$FINAL_DMG" >/dev/null

# Finder treats a DMG file icon and a mounted-volume icon as separate assets.
# Embed the same mark into the DMG resource fork so both surfaces stay branded.
cp "$ICON_FILE" "$DMG_ICON"
sips -i "$DMG_ICON" >/dev/null
DeRez -only icns "$DMG_ICON" > "$ICON_RSRC"
Rez -append "$ICON_RSRC" -o "$FINAL_DMG"
SetFile -a C "$FINAL_DMG"

echo "$FINAL_DMG"
