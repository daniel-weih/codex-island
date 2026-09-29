#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"

BUILD_ARGS=(-c release "$@")
if [[ -n "${CODEX_ISLAND_BUILD_DIR:-}" ]]; then
    BUILD_ARGS+=(--scratch-path "$CODEX_ISLAND_BUILD_DIR")
fi
swift build "${BUILD_ARGS[@]}" >&2
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
APP_DIR="${CODEX_ISLAND_APP_DIR:-$ROOT_DIR/dist/Codex Island.app}"
RESOURCE_BUNDLE="$BIN_DIR/CodexIsland_CodexIsland.bundle"

if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
    echo "Missing SwiftPM resource bundle: $RESOURCE_BUNDLE" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
install -m 755 "$BIN_DIR/CodexIsland" "$APP_DIR/Contents/MacOS/Codex Island"
install -m 644 "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
install -m 644 "$ROOT_DIR/Packaging/CodexIsland.icns" "$APP_DIR/Contents/Resources/CodexIsland.icns"

/usr/bin/ditto \
    "$RESOURCE_BUNDLE" \
    "$APP_DIR/Contents/Resources/CodexIsland_CodexIsland.bundle"

# Swift release binaries retain local source paths in debug symbols. Strip them
# before signing so distributed builds do not expose the builder's home path.
strip -S "$APP_DIR/Contents/MacOS/Codex Island"

codesign --force --deep --sign - "$APP_DIR"

# Validate through the packaged executable's real loader, without app startup.
# The loader has no fallback to the build directory, so this checks portability.
"$APP_DIR/Contents/MacOS/Codex Island" --check-resources

echo "$APP_DIR"
