#!/usr/bin/env bash
# Downloads AdMob SPM binary artifacts and registers them in workspace-state.json.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DD=$(ls -d ~/Library/Developer/Xcode/DerivedData/JBMRSports-* 2>/dev/null | head -1)
[[ -n "$DD" ]] || { echo "Open/build project in Xcode once first."; exit 1; }

ART="$DD/SourcePackages/artifacts"
STATE="$DD/SourcePackages/workspace-state.json"

GMA_ZIP="https://dl.google.com/googleadmobadssdk/f2c09c60ee331ce0/googlemobileadsios-spm-11.13.0.zip"
GMA_CHECKSUM="f2c09c60ee331ce029f563304ad73a481d57ace0d4bc11ce33a2bf59497c59bf"
UMP_ZIP="https://dl.google.com/googleadmobadssdk/bd2f30ebe527900b/googleusermessagingplatformios-spm-2.7.0.zip"
UMP_CHECKSUM="bd2f30ebe527900b8d789e5e54831b021d032e7dbfd73b90e6f73c2a48b1c683"

fetch_xcframework() {
  local url="$1"
  local checksum="$2"
  local identity="$3"
  local target="$4"
  local dest="$ART/$identity/$target/${target}.xcframework"

  if [[ -d "$dest" ]]; then
    echo "Already present: $target"
    return 0
  fi

  local tmp
  tmp=$(mktemp -d)
  local zip="$tmp/archive.zip"
  echo "Downloading $target..."
  curl -fsSL "$url" -o "$zip"
  local actual
  actual=$(shasum -a 256 "$zip" | awk '{print $1}')
  if [[ "$actual" != "$checksum" ]]; then
    echo "Checksum mismatch for $target (expected $checksum, got $actual)" >&2
    exit 1
  fi
  unzip -q "$zip" -d "$tmp/extract"
  mkdir -p "$ART/$identity/$target"
  ditto "$tmp/extract/${target}.xcframework" "$dest"
  rm -rf "$tmp"
  echo "Installed $dest"
}

fetch_xcframework "$GMA_ZIP" "$GMA_CHECKSUM" \
  "swift-package-manager-google-mobile-ads" "GoogleMobileAds"
fetch_xcframework "$UMP_ZIP" "$UMP_CHECKSUM" \
  "swift-package-manager-google-user-messaging-platform" "UserMessagingPlatform"

python3 <<PY
import json
from pathlib import Path

art = "$ART"
state_path = Path("$STATE")
state = json.loads(state_path.read_text())
arts = state["object"].setdefault("artifacts", [])
seen = {a.get("targetName") for a in arts}

entries = [
    {
        "kind": {"xcframework": {}},
        "packageRef": {
            "identity": "swift-package-manager-google-mobile-ads",
            "kind": "remoteSourceControl",
            "location": "https://github.com/googleads/swift-package-manager-google-mobile-ads.git",
            "name": "GoogleMobileAds",
        },
        "path": f"{art}/swift-package-manager-google-mobile-ads/GoogleMobileAds/GoogleMobileAds.xcframework",
        "source": {
            "checksum": "$GMA_CHECKSUM",
            "type": "remote",
            "url": "$GMA_ZIP",
        },
        "targetName": "GoogleMobileAds",
    },
    {
        "kind": {"xcframework": {}},
        "packageRef": {
            "identity": "swift-package-manager-google-user-messaging-platform",
            "kind": "remoteSourceControl",
            "location": "https://github.com/googleads/swift-package-manager-google-user-messaging-platform.git",
            "name": "GoogleUserMessagingPlatform",
        },
        "path": f"{art}/swift-package-manager-google-user-messaging-platform/UserMessagingPlatform/UserMessagingPlatform.xcframework",
        "source": {
            "checksum": "$UMP_CHECKSUM",
            "type": "remote",
            "url": "$UMP_ZIP",
        },
        "targetName": "UserMessagingPlatform",
    },
]

for entry in entries:
    if entry["targetName"] not in seen:
        arts.append(entry)

state_path.write_text(json.dumps(state, indent=2) + "\n")
print("Updated workspace-state.json")
PY

cd "$ROOT"
xcodebuild -scheme JBMRSports -destination 'generic/platform=iOS' -configuration Debug \
  -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile build
