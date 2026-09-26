#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
CONFIGURATION="${1:-debug}"

BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.example.codex-account-manager}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION"

BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$ROOT_DIR/.build/codex-account-manager.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/codex-account-manager" "$APP_DIR/Contents/MacOS/codex-account-manager"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_IDENTIFIER" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/codex-account-manager-icon.icns" "$APP_DIR/Contents/Resources/codex-account-manager-icon.icns"
cp "$ROOT_DIR/Resources/codex-account-manager-icon.png" "$APP_DIR/Contents/Resources/codex-account-manager-icon.png"
cp "$ROOT_DIR/Resources/codex-account-manager-status-icon.svg" "$APP_DIR/Contents/Resources/codex-account-manager-status-icon.svg"
chmod +x "$APP_DIR/Contents/MacOS/codex-account-manager"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR"
    print "Signed with: $SIGNING_IDENTITY"
else
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "$APP_DIR"
