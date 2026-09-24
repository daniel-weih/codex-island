#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/.build/parser-checks"
OUTPUT="$OUTPUT_DIR/ParserChecks"
SCREENSHOT_OUTPUT_DIR="$ROOT_DIR/.build/screenshot-checks"
SCREENSHOT_OUTPUT="$SCREENSHOT_OUTPUT_DIR/ScreenshotChecks"
RESET_OUTPUT_DIR="$ROOT_DIR/.build/reset-subscription-checks"
RESET_OUTPUT="$RESET_OUTPUT_DIR/ResetSubscriptionChecks"
MODULE_CACHE="$ROOT_DIR/.build/test-module-cache"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$SCREENSHOT_OUTPUT_DIR"
mkdir -p "$RESET_OUTPUT_DIR"
swiftc \
    -module-cache-path "$MODULE_CACHE" \
    -parse-as-library \
    "$ROOT_DIR/Sources/CodexIsland/CodexModels.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexCreditRateCard.swift" \
    "$ROOT_DIR/Sources/CodexIsland/IslandLanguage.swift" \
    "$ROOT_DIR/Sources/CodexIsland/IslandDisplaySelection.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexUsageTimeline.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexExecutableLocator.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexLauncher.swift" \
    "$ROOT_DIR/Sources/CodexIsland/LaunchAtLoginSetting.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexStatusPayloadParser.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadSettingsReader.swift" \
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

swiftc \
    -module-cache-path "$MODULE_CACHE" \
    -parse-as-library \
    "$ROOT_DIR/Sources/CodexIsland/CodexModels.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexCreditRateCard.swift" \
    "$ROOT_DIR/Sources/CodexIsland/IslandLanguage.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexUsageTimeline.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexExecutableLocator.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexAppServerClient.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexStatusPayloadParser.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadSettingsReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadActivityReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadCreditUsageReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexDailyTokenUsageReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/ResetSubscriptionModels.swift" \
    "$ROOT_DIR/Sources/CodexIsland/ResetSubscriptionSource.swift" \
    "$ROOT_DIR/Sources/CodexIsland/ResetSubscriptionService.swift" \
    "$ROOT_DIR/Sources/CodexIsland/ResetSubscriptionUsage.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexResetAnalyzer.swift" \
    "$ROOT_DIR/Tests/ResetSubscriptionChecks/main.swift" \
    -o "$RESET_OUTPUT"

"$RESET_OUTPUT"

"$ROOT_DIR/scripts/test-reset-analyzer.sh"
