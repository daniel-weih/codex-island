#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$ROOT_DIR/dist/Codex Island.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
install -m 755 "$BIN_DIR/CodexIsland" "$APP_DIR/Contents/MacOS/Codex Island"
install -m 644 "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
install -m 644 "$ROOT_DIR/Packaging/CodexIsland.icns" "$APP_DIR/Contents/Resources/CodexIsland.icns"

RESOURCE_BUNDLE="$BIN_DIR/CodexIsland_CodexIsland.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    /usr/bin/ditto \
        "$RESOURCE_BUNDLE" \
        "$APP_DIR/Contents/Resources/CodexIsland_CodexIsland.bundle"
fi

# Swift release binaries retain local source paths in debug symbols. Strip them
# before signing so distributed builds do not expose the builder's home path.
strip -S "$APP_DIR/Contents/MacOS/Codex Island"

codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
