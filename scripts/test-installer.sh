#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
OUTPUT_DIR="$(mktemp -d /tmp/codex-island-installer-checks.XXXXXX)"
trap 'rm -rf "$OUTPUT_DIR"' EXIT
swiftc -swift-version 5 -parse-as-library \
    -module-cache-path "$OUTPUT_DIR/module-cache" \
    "$ROOT_DIR/Packaging/Installer/AppInstaller.swift" \
    "$ROOT_DIR/Tests/InstallerChecks/main.swift" \
    -o "$OUTPUT_DIR/InstallerChecks"
"$OUTPUT_DIR/InstallerChecks" "$OUTPUT_DIR/fixtures"
