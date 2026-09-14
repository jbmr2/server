#!/usr/bin/env bash
# Xcode BAND karke run karo (Cmd+Q)
set -euo pipefail
PBX="/Users/jbmrsports/jbmr ott app final/JBMRSports.xcodeproj/project.pbxproj"
perl -pi -e 's/PRODUCT_BUNDLE_IDENTIFIER = com\.jbmrsports\.ott;/PRODUCT_BUNDLE_IDENTIFIER = in.jbmrsports.ott;/g' "$PBX"
perl -pi -e 's/DEVELOPMENT_TEAM = 9Z6NFGSD29;/DEVELOPMENT_TEAM = SJ536RSC6J;/g' "$PBX"
perl -pi -e 's/DEVELOPMENT_TEAM = "";/DEVELOPMENT_TEAM = SJ536RSC6J;/g' "$PBX"
echo "OK: signing in.jbmrsports.ott + team LOKESH LOKESH"
