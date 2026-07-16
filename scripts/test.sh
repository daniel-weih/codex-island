#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/.build/parser-checks"
OUTPUT="$OUTPUT_DIR/ParserChecks"

mkdir -p "$OUTPUT_DIR"
swiftc \
    -parse-as-library \
    "$ROOT_DIR/Sources/CodexIsland/CodexModels.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexUsageTimeline.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexExecutableLocator.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexLauncher.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexStatusPayloadParser.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadSettingsReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadActivityReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexDailyTokenUsageReader.swift" \
    "$ROOT_DIR/Tests/ParserChecks/main.swift" \
    -o "$OUTPUT"

"$OUTPUT"
