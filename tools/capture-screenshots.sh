#!/usr/bin/env bash
# Captures App Store screenshots on iPhone 17 Pro Max simulator.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/AppStoreScreenshots"
PBX="$ROOT/JBMRSports.xcodeproj/project.pbxproj"
PBX_BACKUP="$PBX.screenshot-backup"
SIM="${SIMULATOR_UDID:-6FA22370-88ED-4CEA-A533-065711B59B12}"
MATCH_ID="${SCREENSHOT_MATCH_ID:-51ace73c-ed53-448b-806e-128682347b06}"
BUNDLE="in.jbmrsports.ott"

cleanup() {
  if [[ -f "$PBX_BACKUP" ]]; then
    mv "$PBX_BACKUP" "$PBX"
  fi
}
trap cleanup EXIT

mkdir -p "$OUT"

disable_admob_for_simulator_build() {
  cp "$PBX" "$PBX_BACKUP"
  python3 <<PY
from pathlib import Path
import re

path = Path("$PBX")
text = path.read_text()
patterns = [
    r"\t\tEC16F4194FF92DBE4E048C02 /\* GoogleMobileAds in Frameworks \*/ = \{isa = PBXBuildFile; productRef = AA9D110EA6530C4049372203 /\* GoogleMobileAds \*/; \};\n",
    r"\t\t\t\tEC16F4194FF92DBE4E048C02 /\* GoogleMobileAds in Frameworks \*/,\n",
    r"\t\t\t\tAA9D110EA6530C4049372203 /\* GoogleMobileAds \*/,\n",
    r"\t\t606F86A7F43E2D24278C4126 /\* XCRemoteSwiftPackageReference \"swift-package-manager-google-mobile-ads\" \*/,\n",
    r"\t\t606F86A7F43E2D24278C4126 /\* XCRemoteSwiftPackageReference \"swift-package-manager-google-mobile-ads\" \*/ = \{[^}]+\};\n",
    r"\t\tAA9D110EA6530C4049372203 /\* GoogleMobileAds \*/ = \{[^}]+\};\n",
]
for pattern in patterns:
    text, count = re.subn(pattern, "", text, flags=re.S)
    if count:
        print(f"removed {count} for pattern")
path.write_text(text)
PY
}

echo "Booting simulator $SIM..."
xcrun simctl boot "$SIM" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$SIM" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$SIM" -b

echo "Preparing simulator build without AdMob link..."
disable_admob_for_simulator_build

echo "Building for simulator..."
cd "$ROOT"
xcodebuild -scheme JBMRSports \
  -destination "platform=iOS Simulator,id=$SIM" \
  -configuration Debug \
  -skipPackageUpdates \
  -onlyUsePackageVersionsFromResolvedFile \
  build >/tmp/jbmr-screenshot-build.log 2>&1 || {
    tail -30 /tmp/jbmr-screenshot-build.log
    exit 1
  }

APP="$(find "$HOME/Library/Developer/Xcode/DerivedData"/JBMRSports-*/Build/Products/Debug-iphonesimulator -maxdepth 1 -name JBMRSports.app 2>/dev/null | head -1)"
[[ -n "$APP" ]] || { echo "Simulator app not found"; exit 1; }

xcrun simctl install "$SIM" "$APP"

capture() {
  local file="$1"
  local wait="${2:-4}"
  sleep "$wait"
  xcrun simctl io "$SIM" screenshot "$OUT/$file"
  echo "Saved $OUT/$file"
}

launch_app() {
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  sleep 1
  xcrun simctl launch "$SIM" "$BUNDLE" -ScreenshotMode "$@" >/dev/null
  osascript -e 'tell application "Simulator" to activate' >/dev/null 2>&1 || true
}

launch_app
capture "01-splash.png" 1

launch_app
capture "02-home.png" 14

launch_app -ScreenshotTab schedule
capture "03-schedule.png" 14

launch_app -ScreenshotMatchID "$MATCH_ID"
capture "04-match-video.png" 16

launch_app -ScreenshotTab shorts
capture "05-shorts.png" 14

launch_app -ScreenshotTab profile
capture "06-profile.png" 12

echo ""
echo "Screenshots ready in: $OUT"
ls -la "$OUT"/*.png
