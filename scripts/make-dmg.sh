#!/bin/bash
# Builds a release Halo.app and wraps it in a drag-to-install DMG.
#   scripts/make-dmg.sh              → build/Halo-<version>.dmg
#   HALO_VERSION=1.1.0 scripts/make-dmg.sh
# Needs dmgbuild: python3 -m venv tools/.venv && tools/.venv/bin/pip install dmgbuild
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${HALO_VERSION:-1.0.0}"
DMGBUILD="${DMGBUILD:-}"
if [[ -z "$DMGBUILD" ]]; then
  if [[ -x tools/.venv/bin/dmgbuild ]]; then DMGBUILD=tools/.venv/bin/dmgbuild
  else DMGBUILD=dmgbuild; fi
fi
export HALO_VERSION="$VERSION"

scripts/build-app.sh release

WORK="$(mktemp -d)"
swift scripts/dmg/make-background.swift "$WORK" >/dev/null
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null 2>&1

OUT="build/Halo-$VERSION.dmg"
rm -f "$OUT"
"$DMGBUILD" -s scripts/dmg/settings.py -D app="build/Halo.app" -D background="$WORK/background.tiff" "Halo" "$OUT"
codesign --force --sign "${HALO_SIGN_IDENTITY:--}" "$OUT" >/dev/null
hdiutil verify "$OUT" >/dev/null
echo "Created $OUT ($(du -h "$OUT" | cut -f1))"
