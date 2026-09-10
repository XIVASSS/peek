#!/usr/bin/env bash
# Build a Glance-style Peek.dmg.
#
# Usage: ./tools/package_dmg.sh
# Output: dist/Peek.dmg  and  dist/Peek-<version>.dmg

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${PEEK_VERSION:-1.1.0}"
SCHEME="glance"
CONFIG="Release"
DERIVED="$ROOT/build/DerivedData"
DIST="$ROOT/dist"
STAGE="$DIST/stage-app"
BG="$ROOT/docs/dmg/background.png"

echo "==> Building Peek ($CONFIG, unsigned then ad-hoc sign)"
xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_SRC="$DERIVED/Build/Products/$CONFIG/Peek.app"
[[ -d "$APP_SRC" ]] || { echo "Missing $APP_SRC"; exit 1; }
[[ -f "$BG" ]] || { echo "Missing $BG"; exit 1; }

echo "==> Staging"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
cp -R "$APP_SRC" "$STAGE/Peek.app"

# Empty entitlements — keychain-access-groups needs a real team cert.
cat > "$DIST/adhoc.entitlements" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
EOF

xattr -cr "$STAGE/Peek.app" || true
codesign --force --deep --sign - --entitlements "$DIST/adhoc.entitlements" "$STAGE/Peek.app"
codesign --verify --deep --strict "$STAGE/Peek.app"

# Helps when Gatekeeper says "damaged" after download (quarantine + unsigned).
cat > "$STAGE/If Peek won't open.command" <<'CMD'
#!/bin/bash
cd "$(dirname "$0")"
TARGET=""
if [[ -d "/Applications/Peek.app" ]]; then
  TARGET="/Applications/Peek.app"
elif [[ -d "./Peek.app" ]]; then
  TARGET="./Peek.app"
fi
if [[ -z "$TARGET" ]]; then
  osascript -e 'display alert "Peek" message "Drag Peek into Applications first, then run this again." as informational'
  exit 1
fi
xattr -cr "$TARGET"
open "$TARGET"
CMD
chmod +x "$STAGE/If Peek won't open.command"

echo "==> Creating DMG"
rm -f "$DIST/Peek.dmg" "$DIST/Peek-${VERSION}.dmg" "$DIST/rw."*.dmg

VOLICON_ARGS=()
if [[ -f "$STAGE/Peek.app/Contents/Resources/AppIcon.icns" ]]; then
  VOLICON_ARGS=(--volicon "$STAGE/Peek.app/Contents/Resources/AppIcon.icns")
fi

create-dmg \
  --volname "Peek" \
  "${VOLICON_ARGS[@]}" \
  --background "$BG" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 100 \
  --icon "Peek.app" 160 250 \
  --hide-extension "Peek.app" \
  --app-drop-link 500 250 \
  --icon "If Peek won't open.command" 330 355 \
  --no-internet-enable \
  "$DIST/Peek.dmg" \
  "$STAGE"

cp -f "$DIST/Peek.dmg" "$DIST/Peek-${VERSION}.dmg"
xattr -cr "$DIST/Peek.dmg" "$DIST/Peek-${VERSION}.dmg" || true
rm -f "$DIST/adhoc.entitlements"

echo "Done:"
ls -lh "$DIST/Peek.dmg" "$DIST/Peek-${VERSION}.dmg"
