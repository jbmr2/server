#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="$ROOT/Builds/JBMRSports-AppStore.xcarchive"
EXPORT_DIR="$ROOT/Builds/AppStore"
TEAM_ID="SJ536RSC6J"

cd "$ROOT"

echo "==> Archive (Release)..."
xcodebuild \
  -scheme JBMRSports \
  -project JBMRSports.xcodeproj \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  -allowProvisioningUpdates \
  archive

echo "==> Export for App Store Connect..."
rm -rf "$EXPORT_DIR"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$ROOT/Builds/ExportOptions-AppStore.plist" \
  -allowProvisioningUpdates

echo ""
echo "Done."
echo "IPA: $EXPORT_DIR/JBMRSports.ipa"
echo "Next: Xcode → Window → Organizer → Distribute App, ya Transporter se upload karo."
