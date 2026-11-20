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
executable="$APP_DIR/Contents/MacOS/Codex Island"
strip -S "$executable"

# SwiftPM can also add the build toolchain's local runtime search path.
# The app uses macOS system libraries and app-relative search paths.
runtime_paths="$(otool -l "$executable" | awk '
    $1 == "cmd" { is_runtime_path = ($2 == "LC_RPATH") }
    is_runtime_path && $1 == "path" {
        sub(/^[[:space:]]*path[[:space:]]+/, "")
        sub(/[[:space:]]+\(offset [0-9]+\)$/, "")
        print
    }
')"
while IFS= read -r runtime_path; do
    case "$runtime_path" in
        /usr/lib/swift|/usr/lib/swift/*|/System/Library/*) ;;
        /*) install_name_tool -delete_rpath "$runtime_path" "$executable" ;;
    esac
done <<< "$runtime_paths"

codesign --force --deep --sign - "$APP_DIR"

# Validate through the packaged executable's real loader, without app startup.
# The loader has no fallback to the build directory, so this checks portability.
"$executable" --check-resources

echo "$APP_DIR"
