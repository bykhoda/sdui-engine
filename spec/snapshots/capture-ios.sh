#!/usr/bin/env bash
# iOS leg of the visual snapshot suite. Runs the SDUISnapshotTests XCTest on an iOS 16+
# simulator; the test renders every fixture from manifest.json through SDUIScreenView via
# ImageRenderer and writes {fixture}.ios.{scheme}.png straight into spec/snapshots/__out__.
# No external dependency (ImageRenderer is system) — offline `xcodebuild test`.
#
# Usage: bash spec/snapshots/capture-ios.sh [light,dark]   (scheme arg reserved; the test
#        renders both schemes itself)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
cd "$REPO/ios"

command -v xcodebuild >/dev/null 2>&1 || { echo "ios: xcodebuild not found (install Xcode)." >&2; exit 3; }

# Prefer a booted simulator; otherwise fall back to a common iPhone by name.
UDID="$(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
if [ -n "${UDID:-}" ]; then
  DEST="platform=iOS Simulator,id=$UDID"
else
  DEST="platform=iOS Simulator,name=iPhone 15"
fi
echo "ios: destination → $DEST"

# SPM's aggregate scheme runs every test target (including SDUISnapshotTests via -only-testing).
SCHEME="SDUI-Package"
echo "ios: scheme → $SCHEME"

xcodebuild test \
  -scheme "$SCHEME" \
  -destination "$DEST" \
  -only-testing:SDUISnapshotTests \
  -resultBundlePath "$HERE/__out__/_ios-result.xcresult" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -iE 'Test Case|SDUI-SNAP|error:|BUILD|Executed|passed|failed' | tail -30

count=$(ls "$HERE/__out__"/*.ios.*.png 2>/dev/null | wc -l | tr -d ' ')
echo "ios: captured $count PNG(s)"
[ "$count" -gt 0 ]
