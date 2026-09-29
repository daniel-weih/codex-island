#!/bin/zsh

set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$1"
shift
SDK_PATH="${SDKROOT:-$(xcrun --show-sdk-path)}"
while (( $# )); do
    case "$1" in
        --sdk) SDK_PATH="$2"; shift 2 ;;
        --sdk=*) SDK_PATH="${1#--sdk=}"; shift ;;
        *) shift ;;
    esac
done
CACHE_DIR="$(mktemp -d /tmp/codex-island-installer-build.XXXXXX)"
trap 'rm -rf "$CACHE_DIR"' EXIT

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/zh_CN.lproj" \
    "$APP_DIR/Contents/Resources/en.lproj"
swiftc -O -swift-version 5 -parse-as-library \
    -sdk "$SDK_PATH" -target "$(uname -m)-apple-macosx13.0" \
    -module-cache-path "$CACHE_DIR" \
    "$ROOT_DIR/Packaging/Installer/AppInstaller.swift" \
    "$ROOT_DIR/Packaging/Installer/InstallerMain.swift" \
    -o "$APP_DIR/Contents/MacOS/Install Codex Island"
strip -S "$APP_DIR/Contents/MacOS/Install Codex Island"
install -m 644 "$ROOT_DIR/Packaging/CodexIsland.icns" "$APP_DIR/Contents/Resources/CodexIsland.icns"
python3 - "$ROOT_DIR/Packaging/Info.plist" "$APP_DIR/Contents/Info.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    app = plistlib.load(stream)
info = {
    "CFBundleDevelopmentRegion": "en",
    "CFBundleDisplayName": "Install or Update Codex Island",
    "CFBundleName": "Install Codex Island",
    "CFBundleExecutable": "Install Codex Island",
    "CFBundleIdentifier": "com.codexisland.installer",
    "CFBundleIconFile": "CodexIsland.icns",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": app["CFBundleShortVersionString"],
    "CFBundleVersion": app["CFBundleVersion"],
    "LSMinimumSystemVersion": "13.0",
    "NSHighResolutionCapable": True,
    "NSPrincipalClass": "NSApplication",
}
with open(sys.argv[2], "wb") as stream:
    plistlib.dump(info, stream)
PY
printf '%s\n' '"CFBundleDisplayName" = "安装或更新 Codex Island";' \
    > "$APP_DIR/Contents/Resources/zh_CN.lproj/InfoPlist.strings"
printf '%s\n' '"CFBundleDisplayName" = "Install or Update Codex Island";' \
    > "$APP_DIR/Contents/Resources/en.lproj/InfoPlist.strings"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
