#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$ROOT_DIR/dist/Codex Island.app"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
install -m 755 "$BIN_DIR/CodexIsland" "$APP_DIR/Contents/MacOS/CodexIsland"
install -m 644 "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
