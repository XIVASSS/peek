#!/usr/bin/env bash
# Build Peek.app and wrap it in a distributable .dmg
#
# Usage:
#   ./tools/package_dmg.sh
#   ./tools/package_dmg.sh --sign "Developer ID Application: Your Name (TEAMID)"
#
# Output: dist/Peek-<version>.dmg

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${PEEK_VERSION:-1.1.0}"
SCHEME="glance"
CONFIG="Release"
DERIVED="$ROOT/build/DerivedData"
DIST="$ROOT/dist"
STAGE="$DIST/dmg-stage"
DMG_NAME="Peek-${VERSION}.dmg"
SIGN_IDENTITY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign) SIGN_IDENTITY="$2"; shift 2 ;;
    --version) VERSION="$2"; DMG_NAME="Peek-${VERSION}.dmg"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo "==> Building Peek ($CONFIG)"
xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_SRC="$(find "$DERIVED/Build/Products/$CONFIG" -maxdepth 1 \( -name 'Peek.app' -o -name 'glance.app' \) -print -quit)"
if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
  echo "Could not find Peek.app under $DERIVED/Build/Products/$CONFIG"
  ls -la "$DERIVED/Build/Products/$CONFIG" || true
  exit 1
fi

echo "==> Staging DMG contents from $APP_SRC"
rm -rf "$STAGE" "$DIST/$DMG_NAME"
mkdir -p "$STAGE" "$DIST"
rm -rf "$STAGE/Peek.app"
cp -R "$APP_SRC" "$STAGE/Peek.app"
ln -sf /Applications "$STAGE/Applications"

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "==> Codesigning Peek.app"
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$STAGE/Peek.app"
fi

echo "==> Creating $DMG_NAME"
hdiutil create \
  -volname "Peek" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DIST/$DMG_NAME"

rm -rf "$STAGE"
echo "Done: $DIST/$DMG_NAME"
ls -lh "$DIST/$DMG_NAME"
