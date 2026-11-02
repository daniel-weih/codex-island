#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/.build/parser-checks"
OUTPUT="$OUTPUT_DIR/ParserChecks"
SCREENSHOT_OUTPUT_DIR="$ROOT_DIR/.build/screenshot-checks"
SCREENSHOT_OUTPUT="$SCREENSHOT_OUTPUT_DIR/ScreenshotChecks"
MODULE_CACHE="$ROOT_DIR/.build/test-module-cache"

"$ROOT_DIR/scripts/test-resources.sh"
"$ROOT_DIR/scripts/test-installer.sh"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/CodexIsland_CodexIsland.bundle"
cp "$ROOT_DIR/Sources/CodexIsland/Resources/CodexCreditRates.json" "$OUTPUT_DIR/CodexIsland_CodexIsland.bundle/"
mkdir -p "$SCREENSHOT_OUTPUT_DIR"
swiftc \
    -module-cache-path "$MODULE_CACHE" \
    -parse-as-library \
    "$ROOT_DIR/Sources/CodexIsland/CodexModels.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexCreditRateCard.swift" \
    "$ROOT_DIR/Sources/CodexIsland/AppResources.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexCreditConfiguration.swift" \
    "$ROOT_DIR/Sources/CodexIsland/IslandLanguage.swift" \
    "$ROOT_DIR/Sources/CodexIsland/IslandPopoverContent.swift" \
    "$ROOT_DIR/Sources/CodexIsland/IslandDisplaySelection.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexUsageTimeline.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexExecutableLocator.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexLauncher.swift" \
    "$ROOT_DIR/Sources/CodexIsland/LaunchAtLoginSetting.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexStatusPayloadParser.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexRolloutLineReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadSettingsReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadServiceTierReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadActivityReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadCreditUsageReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexDailyTokenUsageReader.swift" \
    "$ROOT_DIR/Tests/ParserChecks/main.swift" \
    -o "$OUTPUT"

"$OUTPUT"

swiftc \
    -module-cache-path "$MODULE_CACHE" \
    -parse-as-library \
    "$ROOT_DIR/Sources/CodexIsland/IslandScreenshotService.swift" \
    "$ROOT_DIR/Tests/ScreenshotChecks/main.swift" \
    -o "$SCREENSHOT_OUTPUT"

"$SCREENSHOT_OUTPUT"

"$ROOT_DIR/scripts/test-configuration.sh"
"$ROOT_DIR/scripts/test-runtime.sh"
"$ROOT_DIR/scripts/test-packaging.sh"
