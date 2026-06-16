#!/usr/bin/env bash
# PeekMark release script
# Usage: ./scripts/release.sh <version>
# Requires: Xcode Developer tools, Apple Developer account configured
# Set these environment variables before running:
#   APPLE_ID          — your Apple ID email
#   APP_PASSWORD      — app-specific password for notarization
#   TEAM_ID           — your 10-character Apple Developer Team ID
#   SPARKLE_KEY_PATH  — path to your Sparkle EdDSA private key

set -euo pipefail

VERSION="${1:?Usage: release.sh <version>}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build/Release"
ARCHIVE_PATH="$PROJECT_DIR/build/Archive/PeekMark.xcarchive"
EXPORT_PATH="$PROJECT_DIR/build/Export"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
APP_PATH="$BUILD_DIR/PeekMark.app"
NOTARY_ZIP="$BUILD_DIR/PeekMark-notary.zip"
DMG_STAGE="$BUILD_DIR/dmg-stage"
ARCHIVES_DIR="$BUILD_DIR/sparkle"
DMG_PATH="$ARCHIVES_DIR/PeekMark-$VERSION.dmg"
SIGN_UPDATE_BIN="${SPARKLE_SIGN_UPDATE_BIN:-sign_update}"
GENERATE_APPCAST_BIN="${SPARKLE_GENERATE_APPCAST_BIN:-generate_appcast}"
DOWNLOAD_URL_PREFIX="${DOWNLOAD_URL_PREFIX:-https://github.com/QuartzInkStudio/PeekMark/releases/download/v$VERSION/}"
PRODUCT_LINK="${PRODUCT_LINK:-https://peekmark.app/}"
TEAM_ID="${TEAM_ID:?Set TEAM_ID}"

mkdir -p "$BUILD_DIR" "$ARCHIVES_DIR" "$EXPORT_PATH"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$APP_PATH" "$NOTARY_ZIP" "$DMG_STAGE" "$DMG_PATH" "$EXPORT_OPTIONS"

/usr/libexec/PlistBuddy -c 'Clear dict' "$EXPORT_OPTIONS" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :method string developer-id' "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string automatic' "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :stripSwiftSymbols bool true' "$EXPORT_OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :destination string export' "$EXPORT_OPTIONS"

echo "==> Building PeekMark $VERSION"
xcodebuild \
  -project "$PROJECT_DIR/PeekMark.xcodeproj" \
  -scheme PeekMark \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  archive

echo "==> Exporting archive"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates

ditto "$EXPORT_PATH/PeekMark.app" "$APP_PATH"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep "TeamIdentifier=$TEAM_ID"

echo "==> Notarizing"
ditto -c -k --norsrc --keepParent "$APP_PATH" "$NOTARY_ZIP"
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
else
  xcrun notarytool submit "$NOTARY_ZIP" \
    --apple-id "${APPLE_ID:?Set APPLE_ID or NOTARY_PROFILE}" \
    --password "${APP_PASSWORD:?Set APP_PASSWORD or NOTARY_PROFILE}" \
    --team-id "$TEAM_ID" \
    --wait
fi

echo "==> Stapling"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

echo "==> Creating DMG"
mkdir -p "$DMG_STAGE"
ditto "$APP_PATH" "$DMG_STAGE/PeekMark.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
  -volname "PeekMark $VERSION" \
  -srcfolder "$DMG_STAGE" \
  -ov -format UDZO \
  "$DMG_PATH"
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n "s/.*\"\(Developer ID Application: .*($TEAM_ID)\)\".*/\1/p" | head -1)}"
if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --verbose=4 "$DMG_PATH"
fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
else
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "${APPLE_ID:?Set APPLE_ID or NOTARY_PROFILE}" \
    --password "${APP_PASSWORD:?Set APP_PASSWORD or NOTARY_PROFILE}" \
    --team-id "$TEAM_ID" \
    --wait
fi
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
hdiutil verify "$DMG_PATH" >/dev/null

echo "==> Signing DMG for Sparkle"
"$SIGN_UPDATE_BIN" --ed-key-file "${SPARKLE_KEY_PATH:?Set SPARKLE_KEY_PATH}" "$DMG_PATH"

echo "==> Updating appcast"
cp "$PROJECT_DIR/docs/appcast.xml" "$ARCHIVES_DIR/appcast.xml"
"$GENERATE_APPCAST_BIN" \
  --ed-key-file "$SPARKLE_KEY_PATH" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --link "$PRODUCT_LINK" \
  --maximum-versions 0 \
  "$ARCHIVES_DIR"
cp "$ARCHIVES_DIR/appcast.xml" "$PROJECT_DIR/docs/appcast.xml"

echo "✅ Release complete: $DMG_PATH"
echo "Next steps:"
echo "  1. Upload $DMG_PATH to GitHub Release v$VERSION"
echo "  2. Commit and push docs/appcast.xml after uploading the release asset"
