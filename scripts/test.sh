#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/.build/parser-checks"
OUTPUT="$OUTPUT_DIR/ParserChecks"
SCREENSHOT_OUTPUT_DIR="$ROOT_DIR/.build/screenshot-checks"
SCREENSHOT_OUTPUT="$SCREENSHOT_OUTPUT_DIR/ScreenshotChecks"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$SCREENSHOT_OUTPUT_DIR"
swiftc \
    -parse-as-library \
    "$ROOT_DIR/Sources/CodexIsland/CodexModels.swift" \
    "$ROOT_DIR/Sources/CodexIsland/IslandLanguage.swift" \
    "$ROOT_DIR/Sources/CodexIsland/IslandDisplaySelection.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexUsageTimeline.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexExecutableLocator.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexLauncher.swift" \
    "$ROOT_DIR/Sources/CodexIsland/LaunchAtLoginSetting.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexStatusPayloadParser.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadSettingsReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadActivityReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexDailyTokenUsageReader.swift" \
    "$ROOT_DIR/Tests/ParserChecks/main.swift" \
    -o "$OUTPUT"

"$OUTPUT"

swiftc \
    -parse-as-library \
    "$ROOT_DIR/Sources/CodexIsland/IslandScreenshotService.swift" \
    "$ROOT_DIR/Tests/ScreenshotChecks/main.swift" \
    -o "$SCREENSHOT_OUTPUT"

"$SCREENSHOT_OUTPUT"
