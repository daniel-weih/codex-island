#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/.build/resource-checks"
mkdir -p "$OUTPUT_DIR"

swiftc \
    -module-cache-path "$ROOT_DIR/.build/test-module-cache" \
    -parse-as-library \
    "$ROOT_DIR/Sources/CodexIsland/AppResources.swift" \
    "$ROOT_DIR/Sources/CodexIsland/TaskSoundPlayer.swift" \
    "$ROOT_DIR/Sources/CodexIsland/IslandColorTheme.swift" \
    "$ROOT_DIR/Sources/CodexIsland/IslandLanguage.swift" \
    "$ROOT_DIR/Tests/ResourceChecks/main.swift" \
    -o "$OUTPUT_DIR/ResourceChecks"

"$OUTPUT_DIR/ResourceChecks" "$ROOT_DIR/Sources/CodexIsland/Resources"
