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
ARCHIVE_PATH="$PROJECT_DIR/build/PeekMark.xcarchive"
EXPORT_PATH="$PROJECT_DIR/build/export"
DMG_PATH="$PROJECT_DIR/build/PeekMark-$VERSION.dmg"
APP_PATH="$EXPORT_PATH/PeekMark.app"
SIGN_UPDATE_BIN="${SPARKLE_SIGN_UPDATE_BIN:-sign_update}"

echo "==> Building PeekMark $VERSION"
xcodebuild \
  -project "$PROJECT_DIR/PeekMark.xcodeproj" \
  -scheme PeekMark \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

echo "==> Exporting archive"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$PROJECT_DIR/scripts/ExportOptions.plist" \
  -exportPath "$EXPORT_PATH"

echo "==> Notarizing"
xcrun notarytool submit "$APP_PATH" \
  --apple-id "${APPLE_ID:?Set APPLE_ID}" \
  --password "${APP_PASSWORD:?Set APP_PASSWORD}" \
  --team-id "${TEAM_ID:?Set TEAM_ID}" \
  --wait

echo "==> Stapling"
xcrun stapler staple "$APP_PATH"

echo "==> Creating DMG"
hdiutil create \
  -volname "PeekMark $VERSION" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "==> Signing DMG for Sparkle"
if [ -n "${SPARKLE_KEY_PATH:-}" ]; then
  "$SIGN_UPDATE_BIN" --ed-key-file "$SPARKLE_KEY_PATH" "$DMG_PATH"
else
  echo "  SPARKLE_KEY_PATH not set — skip EdDSA signature (set it for production release)"
fi

echo "✅ Release complete: $DMG_PATH"
echo "Next steps:"
echo "  1. Upload $DMG_PATH to GitHub Release v$VERSION"
echo "  2. Update https://peekmark.app/appcast.xml with new version/signature"
