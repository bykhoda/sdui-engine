#!/usr/bin/env bash
# iOS leg of the visual snapshot suite. A headless XCTest can't render SwiftUI content (an
# SPM test bundle has no render server), so this builds + launches the DemoApp in its
# SDUI_SNAPSHOT mode instead: a real foreground app WITH a render server renders every
# fixture from manifest.json and writes {fixture}.ios.{scheme}.png into spec/snapshots/__out__
# (the simulator shares the host filesystem). See ios/Examples/DemoApp/Sources/Snapshotter.swift.
#
# Usage: bash spec/snapshots/capture-ios.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
PROJ="$REPO/ios/Examples/DemoApp/SDUIDemo.xcodeproj"
BUNDLE="dev.sdui.demo"
DD="$HERE/__out__/_ios-dd"

command -v xcodebuild >/dev/null 2>&1 || { echo "ios: xcodebuild not found (install Xcode)." >&2; exit 3; }

# Prefer a booted simulator; otherwise boot a common iPhone.
UDID="$(xcrun simctl list devices booted 2>/dev/null | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
if [ -z "${UDID:-}" ]; then
  UDID="$(xcrun simctl list devices available 2>/dev/null | grep -m1 -E 'iPhone 1[456]' | grep -oE '[0-9A-F-]{36}' | head -1 || true)"
  [ -n "${UDID:-}" ] || { echo "ios: no iOS simulator available." >&2; exit 3; }
  xcrun simctl boot "$UDID" || true
fi
echo "ios: simulator $UDID"

echo "ios: building DemoApp (snapshot host) …"
xcodebuild -project "$PROJ" -scheme SDUIDemo -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DD" \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -iE 'error:|BUILD (SUCCEEDED|FAILED)' | tail -20

APP="$DD/Build/Products/Debug-iphonesimulator/SDUIDemo.app"
[ -d "$APP" ] || { echo "ios: build produced no app at $APP" >&2; exit 1; }
xcrun simctl install "$UDID" "$APP"

echo "ios: rendering (SDUI_SNAPSHOT) …"
# SIMCTL_CHILD_* passes env into the launched app; --console blocks until it exit(0)s.
SIMCTL_CHILD_SDUI_SNAPSHOT=1 SIMCTL_CHILD_SDUI_REPO="$REPO" \
  xcrun simctl launch --console-pty --terminate-running-process "$UDID" "$BUNDLE" 2>&1 | grep -iE 'SDUI-SNAP' | tail -3 || true

count=$(ls "$HERE/__out__"/*.ios.*.png 2>/dev/null | wc -l | tr -d ' ')
echo "ios: captured $count PNG(s)"
[ "$count" -gt 0 ]
