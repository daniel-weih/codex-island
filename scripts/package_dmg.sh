#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
DIST_DIR="$ROOT_DIR/dist"
WORK_DIR="$(mktemp -d /tmp/codex-island-package.XXXXXX)"
APP_DIR="$WORK_DIR/Codex Island.app"
STAGE_DIR="$WORK_DIR/stage"
RW_DMG="$WORK_DIR/Codex-Island-rw.dmg"
BUILT_DMG="$WORK_DIR/Codex-Island.dmg"
FINAL_DMG="$DIST_DIR/Codex-Island.dmg"
DMG_ICON_FILE="$ROOT_DIR/Packaging/CodexIslandDMG.icns"
DMG_ICON="$WORK_DIR/CodexIsland-dmg-icon.icns"
ICON_RSRC="$WORK_DIR/CodexIsland-icon.rsrc"
MOUNT_DIR="$WORK_DIR/mount"
MOUNTED=0

detach_image() {
    local attempt
    # Resource validation or Finder can briefly keep the image busy after
    # their work ends. Retry without forcing an in-use volume to unmount.
    for attempt in 1 2 3; do
        if hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1; then
            MOUNTED=0
            return 0
        fi
        if (( attempt < 3 )); then sleep 1; fi
    done
    return 1
}

cleanup() {
    if (( MOUNTED )); then
        if ! detach_image; then
            echo "Could not detach $MOUNT_DIR; temporary files retained at $WORK_DIR" >&2
            return
        fi
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [[ -L "$DIST_DIR" ]]; then
    echo "Refusing to clean a symlinked output directory: $DIST_DIR" >&2
    exit 1
fi
mkdir -p "$DIST_DIR" "$MOUNT_DIR"

CODEX_ISLAND_BUILD_DIR="$WORK_DIR/build" \
CODEX_ISLAND_APP_DIR="$APP_DIR" \
    "$ROOT_DIR/scripts/package_app.sh" "$@" >/dev/null

mkdir -p "$STAGE_DIR"
ditto "$APP_DIR" "$STAGE_DIR/Codex Island.app"
"$ROOT_DIR/scripts/package_installer.sh" "$STAGE_DIR/Install Codex Island.app" "$@"
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

install -m 644 "$DMG_ICON_FILE" "$MOUNT_DIR/.VolumeIcon.icns"
SetFile -a C "$MOUNT_DIR"
sync

detach_image

hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$BUILT_DMG" >/dev/null

# Finder treats a DMG file icon and a mounted-volume icon as separate assets.
# Generic files do not receive the app-bundle mask, so use the DMG-specific
# transparent icon for both surfaces instead of exposing the square artwork.
cp "$DMG_ICON_FILE" "$DMG_ICON"
sips -i "$DMG_ICON" >/dev/null
DeRez -only icns "$DMG_ICON" > "$ICON_RSRC"
Rez -append "$ICON_RSRC" -o "$BUILT_DMG"
SetFile -a C "$BUILT_DMG"

hdiutil verify "$BUILT_DMG" >/dev/null
hdiutil attach -readonly -nobrowse -noautoopen \
    -mountpoint "$MOUNT_DIR" "$BUILT_DMG" >/dev/null
MOUNTED=1
codesign --verify --deep --strict "$MOUNT_DIR/Codex Island.app"
"$MOUNT_DIR/Codex Island.app/Contents/MacOS/Codex Island" --check-resources
codesign --verify --deep --strict "$MOUNT_DIR/Install Codex Island.app"
"$MOUNT_DIR/Install Codex Island.app/Contents/MacOS/Install Codex Island" --verify-only
[[ "$(readlink "$MOUNT_DIR/Applications")" == /Applications ]]
detach_image

# Publish only a verified DMG. A failed build keeps the previous output intact.
mv -f "$BUILT_DMG" "$FINAL_DMG"
for artifact in "$DIST_DIR"/*(DN); do
    if [[ -f "$artifact" && "${artifact:e:l}" == dmg ]]; then
        continue
    fi
    rm -rf -- "$artifact"
done

echo "$FINAL_DMG"
