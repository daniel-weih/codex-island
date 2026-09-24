#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$ROOT_DIR/.build/reset-analyzer-checks"
mkdir -p "$OUTPUT_DIR"

# RESET_TEST_SDK overrides SDKROOT and the SDK selected by xcrun.
RESET_SDK="${RESET_TEST_SDK:-${SDKROOT:-$(xcrun --show-sdk-path)}}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$OUTPUT_DIR/ModuleCache}"
swiftc -sdk "$RESET_SDK" -parse-as-library \
    "$ROOT_DIR/Tests/ResetAnalyzerChecks/JSONSupport.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexAppServerClient.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexExecutableLocator.swift" \
    "$ROOT_DIR/Sources/CodexIsland/ResetSubscriptionModels.swift" \
    "$ROOT_DIR/Sources/CodexIsland/CodexResetAnalyzer.swift" \
    "$ROOT_DIR/Tests/ResetAnalyzerChecks/main.swift" \
    -o "$OUTPUT_DIR/ResetAnalyzerChecks"

# The only child process is this deterministic fixture. No real model, account,
# network request, or persisted user setting is used by these checks.
CODEX_CLI_PATH="$ROOT_DIR/Tests/ResetAnalyzerChecks/mock-codex.py" \
    RESET_FIXTURE_MODE=success "$OUTPUT_DIR/ResetAnalyzerChecks"
