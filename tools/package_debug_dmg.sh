#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
    print -u2 "xcodegen is required"
    exit 1
fi

xcodegen generate
xcodebuild \
    -project MoyuPro.xcodeproj \
    -scheme MoyuPro \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath build/DerivedData \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    build

APP_PATH="build/DerivedData/Build/Products/Release/MoyuPro.app"
DIST_DIR="build/dist"
DMG_PATH="$DIST_DIR/大墨鱼-debug-$(date +%Y%m%d-%H%M%S).dmg"
STAGING_DIR="build/dmg-staging"

rm -rf "$STAGING_DIR"
mkdir -p "$DIST_DIR" "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/大墨鱼.app"
ln -s /Applications "$STAGING_DIR/应用程序"

codesign \
    --force \
    --sign - \
    --options runtime \
    --entitlements MoyuPro/Support/MoyuPro.entitlements \
    "$STAGING_DIR/大墨鱼.app"
codesign --verify --deep --strict "$STAGING_DIR/大墨鱼.app"
codesign -dv --verbose=4 "$STAGING_DIR/大墨鱼.app" 2>&1 | tee "$DIST_DIR/latest-signature.txt"
codesign -d --entitlements :- "$STAGING_DIR/大墨鱼.app" 2>&1 | tee "$DIST_DIR/latest-entitlements.xml"
file "$STAGING_DIR/大墨鱼.app/Contents/MacOS/MoyuPro" | tee "$DIST_DIR/latest-architecture.txt"

if ! grep -q '<key>com.apple.security.device.camera</key>' "$DIST_DIR/latest-entitlements.xml"; then
    print -u2 "Camera entitlement is missing"
    exit 1
fi
if grep -q '<key>com.apple.security.app-sandbox</key>' "$DIST_DIR/latest-entitlements.xml"; then
    print -u2 "App Sandbox must remain disabled for Accessibility window switching"
    exit 1
fi
if ! grep -q 'universal binary' "$DIST_DIR/latest-architecture.txt"; then
    print -u2 "Release binary must contain arm64 and x86_64 architectures"
    exit 1
fi

hdiutil create \
    -volname "大墨鱼 Debug" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

hdiutil verify "$DMG_PATH"
shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"
print "Created: $DMG_PATH"
print "Install this DMG only for debugging. It is ad-hoc signed and not notarized."
