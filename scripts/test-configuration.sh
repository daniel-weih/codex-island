#!/bin/zsh
set -euo pipefail
ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/.build/configuration-checks"
mkdir -p "$OUTPUT_DIR/CodexIsland_CodexIsland.bundle"
cp "$ROOT_DIR/Sources/CodexIsland/Resources/CodexCreditRates.json" "$OUTPUT_DIR/CodexIsland_CodexIsland.bundle/"
RUNTIME_SDK="${SDKROOT:-$(xcrun --show-sdk-path)}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$OUTPUT_DIR/ModuleCache}"
swiftc -sdk "$RUNTIME_SDK" -parse-as-library \
    "$ROOT_DIR/Sources/CodexIsland/CodexModels.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexCreditRateCard.swift" \
    "$ROOT_DIR/Sources/CodexIsland/AppResources.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexCreditConfiguration.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexExecutableLocator.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexAppServerClient.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexStatusPayloadParser.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexRolloutLineReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadSettingsReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexThreadCreditUsageReader.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexConfigurationRefresh.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexArtificialAnalysis.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexConfigurationService.swift" \
    "$ROOT_DIR/Sources/CodexIsland/IslandNavigation.swift" \
    "$ROOT_DIR/Tests/ConfigurationChecks/main.swift" \
    -o "$OUTPUT_DIR/ConfigurationChecks"

"$OUTPUT_DIR/ConfigurationChecks" "$ROOT_DIR" "$@"
