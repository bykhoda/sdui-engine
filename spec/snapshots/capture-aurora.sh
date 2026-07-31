#!/usr/bin/env bash
# Aurora leg of the visual snapshot suite. Builds the SduiPlayground for the Aurora
# emulator, deploys it, runs its headless `--snapshot` mode (renders every bundled screen
# through the real renderer — see aurora/qml/Snapshotter.qml), and pulls the PNGs into
# spec/snapshots/__out__ named {fixture}.aurora.{scheme}.png for stitch.mjs / sheet.mjs.
#
# The renderer needs Silica + QtGraphicalEffects, so — unlike the JVM Android leg — this
# MUST run against a real Aurora target (the emulator). It requires the Aurora SDK (`sfdk`)
# and a RUNNING emulator. When either is missing it exits non-zero with guidance, and
# run.mjs simply skips the leg (Aurora stays a visible gap in the gallery, never silent).
#
# Usage: bash spec/snapshots/capture-aurora.sh [light,dark]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/__out__"
SCHEMES="${1:-light,dark}"
APP="ru.auroraos.SduiPlayground"
REMOTE_DIR="/tmp/sdui-snap"
mkdir -p "$OUT"

# ── Locate the Aurora SDK CLI (sfdk). Not on PATH by default; it ships in the SDK. ──────
find_sfdk() {
  command -v sfdk 2>/dev/null && return 0
  for c in "$HOME/AuroraOS/bin/sfdk" "$HOME/AuroraOS/sdk/bin/sfdk" "$HOME/AuroraOS"/*/bin/sfdk; do
    [ -x "$c" ] && { echo "$c"; return 0; }
  done
  return 1
}
SFDK="$(find_sfdk || true)"
if [ -z "${SFDK:-}" ]; then
  echo "aurora: sfdk not found — install the Aurora SDK, then re-run." >&2
  echo "        (looked on PATH and under ~/AuroraOS)" >&2
  exit 3
fi

# A running emulator/device is required — the QML renderer can't run on host Qt.
if ! "$SFDK" device list 2>/dev/null | grep -qiE 'emulator|device'; then
  echo "aurora: no Aurora emulator/device registered with sfdk." >&2
  echo "        Start the Aurora Emulator (Qt Creator ▸ Devices, or the SDK), then re-run." >&2
  exit 3
fi

echo "aurora: building $APP with $SFDK …"
( cd "$REPO/aurora" && "$SFDK" build ) || { echo "aurora: build failed" >&2; exit 1; }

echo "aurora: deploying to the emulator …"
( cd "$REPO/aurora" && "$SFDK" deploy --sdk ) || { echo "aurora: deploy failed" >&2; exit 1; }

# ── Capture each scheme, then pull the PNGs back into __out__. ──────────────────────────
IFS=',' read -ra WANT <<< "$SCHEMES"
for scheme in "${WANT[@]}"; do
  echo "aurora: rendering scheme=$scheme …"
  "$SFDK" device exec "mkdir -p $REMOTE_DIR && /usr/bin/$APP --snapshot $REMOTE_DIR $scheme" \
    || { echo "aurora: snapshot run failed (scheme $scheme)" >&2; exit 1; }
done

echo "aurora: pulling PNGs → $OUT"
# sfdk exposes the device over ssh; copy the rendered PNGs into the review tree.
"$SFDK" device exec "ls $REMOTE_DIR/*.png" 2>/dev/null | while read -r remote; do
  base="$(basename "$remote")"
  "$SFDK" device pull "$remote" "$OUT/$base" 2>/dev/null || true
done

count=$(ls "$OUT"/*.aurora.*.png 2>/dev/null | wc -l | tr -d ' ')
echo "aurora: captured $count PNG(s) into $OUT"
[ "$count" -gt 0 ]
