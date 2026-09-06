#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

PROJECT_ROOT="$(pwd)"
APP_NAME="Geranium"
BUILD_ROOT="$PROJECT_ROOT/build"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
BUILT_APP="$DERIVED_DATA/Build/Products/Release-iphoneos/$APP_NAME.app"
TARGET_APP="$BUILD_ROOT/$APP_NAME.app"
TARGET_TIPA="$BUILD_ROOT/$APP_NAME.tipa"

rm -rf "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT"

xcodebuild \
    -project "$PROJECT_ROOT/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "generic/platform=iOS" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO

cp -R "$BUILT_APP" "$TARGET_APP"
codesign --remove-signature "$TARGET_APP" 2>/dev/null || true
rm -rf "$TARGET_APP/_CodeSignature"
rm -f "$TARGET_APP/embedded.mobileprovision"

if ! command -v ldid >/dev/null 2>&1; then
    echo "ldid is required. Install it before running this script."
    exit 1
fi

ldid -S"$PROJECT_ROOT/entitlements.plist" "$TARGET_APP/$APP_NAME"

EXTENSION_BINARY="$TARGET_APP/PlugIns/Bookmark Location in Geranium.appex/Bookmark Location in Geranium"
if [ -f "$EXTENSION_BINARY" ]; then
    ldid \
        -S"$PROJECT_ROOT/Bookmark Location in Geranium/Bookmark Location in Geranium.entitlements" \
        "$EXTENSION_BINARY"
fi

PAYLOAD_DIR="$BUILD_ROOT/Payload"
mkdir -p "$PAYLOAD_DIR"
cp -R "$TARGET_APP" "$PAYLOAD_DIR/$APP_NAME.app"
(
    cd "$BUILD_ROOT"
    zip -qry "$TARGET_TIPA" Payload
)

rm -rf "$PAYLOAD_DIR" "$TARGET_APP"
echo "Created $TARGET_TIPA"
