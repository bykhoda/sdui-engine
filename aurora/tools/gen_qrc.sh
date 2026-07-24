#!/usr/bin/env sh
# Generates aurora/resources.qrc and content-manifest.json, bundling the SHARED
# playground content (catalog + screens + nav + tokens) that the iOS demo owns,
# via <file alias=...> so there is exactly ONE authored copy across
# iOS / Android / Aurora. Re-run whenever screens are added or removed.
#
#   sh aurora/tools/gen_qrc.sh
set -eu

cd "$(dirname "$0")/.."                       # -> aurora/
SRC="../ios/Sources/SDUIPlayground/Content"   # the single source of truth on disk
QRC="resources.qrc"

# Build the manifest (a list of bundled screen files) first: QML/QRC cannot
# enumerate a resource directory at runtime, so the app reads this to discover
# every screen — the Aurora analogue of iOS's Bundle.urls(forResources:).
manifest="content-manifest.json"
{
  printf '{\n  "screens": [\n'
  first=1
  for d in screens nav; do
    for p in "$SRC/$d"/*.json; do
      [ -e "$p" ] || continue
      b=$(basename "$p")
      [ "$first" -eq 1 ] || printf ',\n'
      printf '    "content/%s/%s"' "$d" "$b"
      first=0
    done
  done
  printf '\n  ]\n}\n'
} > "$manifest"

# Build the QRC. Aliases point at the shared iOS Content, so nothing is copied.
{
  printf '<!DOCTYPE RCC><RCC version="1.0">\n'
  printf '  <qresource prefix="/">\n'
  printf '    <file alias="content/catalog.json">%s/catalog.json</file>\n' "$SRC"
  printf '    <file alias="content/tokens.json">%s/tokens.json</file>\n' "$SRC"
  printf '    <file alias="content/manifest.json">%s</file>\n' "$manifest"
  for d in screens nav; do
    for p in "$SRC/$d"/*.json; do
      [ -e "$p" ] || continue
      b=$(basename "$p")
      printf '    <file alias="content/%s/%s">%s/%s/%s</file>\n' "$d" "$b" "$SRC" "$d" "$b"
    done
  done
  printf '  </qresource>\n'
  printf '</RCC>\n'
} > "$QRC"

echo "wrote $QRC and $manifest ($(grep -c '<file' "$QRC") files bundled)"
