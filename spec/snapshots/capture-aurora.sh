#!/usr/bin/env bash
# Aurora leg of the visual snapshot suite. Renders every bundled screen through the app's
# headless `--snapshot` mode (aurora/qml/Snapshotter.qml → grabToImage) on a RUNNING Aurora
# emulator, then pulls the PNGs into spec/snapshots/__out__ named {fixture}.aurora.{scheme}.png.
#
# PREREQUISITE: the app must already be built + deployed to the emulator once (via the Aurora
# SDK / Qt Creator with the Docker build engine — the CLI sfdk in this SDK can't build). After
# that, this script re-captures without a rebuild.
#
# Why launch the binary directly (not via invoker): invoker wraps the app in sailjail/firejail,
# which (a) detaches stdout and (b) sandboxes the filesystem so grabbed PNGs can't be written
# where we can pull them. Launching /usr/bin/<app> directly with the compositor's Wayland env
# bypasses the sandbox; the app writes into ~/Pictures (granted via the .desktop Permissions)
# which is a real, ssh-readable dir. IMPORTANT: kill the old instance with `pkill <name>` (NOT
# `pkill -f`), or the pattern matches this very ssh command line and kills the session.
#
# Usage: bash spec/snapshots/capture-aurora.sh [light,dark]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/__out__"
SCHEMES="${1:-light,dark}"
mkdir -p "$OUT"

# Emulator connection (overridable). Defaults match the Aurora SDK emulator.
AURORA_KEY="${AURORA_KEY:-$HOME/AuroraOS/vmshare/ssh/private_keys/sdk}"
AURORA_HOST="${AURORA_HOST:-defaultuser@127.0.0.1}"
AURORA_PORT="${AURORA_PORT:-2223}"
APP="ru.auroraos.SduiPlayground"
REMOTE_DIR="/home/defaultuser/Pictures"   # granted by the .desktop Permissions=Pictures

SSH="ssh -i $AURORA_KEY -p $AURORA_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8"

[ -f "$AURORA_KEY" ] || { echo "aurora: ssh key not found: $AURORA_KEY" >&2; exit 3; }
$SSH "$AURORA_HOST" 'echo ok' >/dev/null 2>&1 || { echo "aurora: emulator not reachable — start it (sfdk emulator start)." >&2; exit 3; }
$SSH "$AURORA_HOST" "test -x /usr/bin/$APP" 2>/dev/null || { echo "aurora: app not deployed — build+deploy once via Qt Creator." >&2; exit 3; }

# The compositor's session env (WAYLAND_DISPLAY is relative to XDG_RUNTIME_DIR on Aurora).
ENV='export XDG_RUNTIME_DIR=/run/user/100000 WAYLAND_DISPLAY=../../display/wayland-0 QT_QPA_PLATFORM=wayland EGL_PLATFORM=wayland DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/100000/dbus/user_bus_socket'

IFS=',' read -ra WANT <<< "$SCHEMES"
for scheme in "${WANT[@]}"; do
  echo "aurora: rendering scheme=$scheme …"
  $SSH "$AURORA_HOST" "pkill $APP 2>/dev/null; sleep 1; rm -f $REMOTE_DIR/*.aurora.$scheme.png
    $ENV
    /usr/bin/$APP --snapshot $REMOTE_DIR $scheme >/dev/null 2>&1
    echo \"aurora: $scheme -> \$(ls $REMOTE_DIR/*.aurora.$scheme.png 2>/dev/null | wc -l) png\""
  scp -i "$AURORA_KEY" -P "$AURORA_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "$AURORA_HOST:$REMOTE_DIR/*.aurora.$scheme.png" "$OUT/" 2>/dev/null || true
done

count=$(ls "$OUT"/*.aurora.*.png 2>/dev/null | wc -l | tr -d ' ')
echo "aurora: captured $count PNG(s) into $OUT"
[ "$count" -gt 0 ]
