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
# Ad-hoc signing breaks Accessibility TCC on every rebuild (new CDHash).
# Default to Apple Development when available so permissions stick like Glance's
# team-signed builds. For public Gatekeeper-clean DMGs, set:
#   PEEK_SIGN_IDENTITY="Developer ID Application: …"
# Keychain uses LocalAuthentication fallback when userPresence ACL isn't available.
IDENTITY="${PEEK_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q 'Apple Development:'; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
  else
    IDENTITY="-"
  fi
fi
MOUNTPOINT="${TMPDIR:-/tmp}/PeekDMGMount-$$"

echo "==> Building Peek ($CONFIG)"
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

echo "==> Staging + signing ($IDENTITY)"
rm -rf "$STAGE"
mkdir -p "$STAGE" "$DIST"
cp -R "$APP_SRC" "$STAGE/Peek.app"
xattr -cr "$STAGE/Peek.app" || true

# Full team entitlements (application-identifier / keychain-access-groups) need a
# Mac provisioning profile or Developer ID — otherwise launchd fails with 163.
# Development / ad-hoc builds use Glance's camera entitlements only.
SIGN_ENTS="$DIST/peek-sign.entitlements"
if [[ "$IDENTITY" == "-" ]]; then
  cat > "$SIGN_ENTS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
EOF
  codesign --force --deep --sign - --entitlements "$SIGN_ENTS" "$STAGE/Peek.app"
elif [[ "$IDENTITY" == Developer\ ID* ]]; then
  cp glance/glance.entitlements "$SIGN_ENTS"
  codesign --force --deep --options runtime --sign "$IDENTITY" \
    --entitlements "$SIGN_ENTS" "$STAGE/Peek.app"
else
  # Apple Development — stable Team ID for Accessibility TCC (Glance-like).
  cat > "$SIGN_ENTS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.device.camera</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-only</key>
	<true/>
</dict>
</plist>
EOF
  codesign --force --deep --sign "$IDENTITY" --entitlements "$SIGN_ENTS" "$STAGE/Peek.app"
fi
codesign --verify --deep --strict "$STAGE/Peek.app"

echo "==> Creating DMG"
rm -f "$DIST/Peek.dmg" "$DIST/Peek-${VERSION}.dmg" "$DIST/rw.Peek.dmg"

VOLICON_ARGS=()
if [[ -f "$STAGE/Peek.app/Contents/Resources/AppIcon.icns" ]]; then
  VOLICON_ARGS=(--volicon "$STAGE/Peek.app/Contents/Resources/AppIcon.icns")
fi

create-dmg \
  --volname "Peek" \
  "${VOLICON_ARGS[@]}" \
  --background "$BG" \
  --window-pos 200 120 \
  --window-size 800 440 \
  --icon-size 180 \
  --text-size 16 \
  --icon "Peek.app" 200 280 \
  --hide-extension "Peek.app" \
  --app-drop-link 600 280 \
  --no-internet-enable \
  "$DIST/Peek.dmg" \
  "$STAGE"

# create-dmg can drop the signature — re-sign inside a read-write image.
echo "==> Re-signing app inside DMG"
hdiutil convert "$DIST/Peek.dmg" -format UDRW -o "$DIST/rw.Peek.dmg" -ov >/dev/null
rm -rf "$MOUNTPOINT"
mkdir -p "$MOUNTPOINT"
hdiutil attach "$DIST/rw.Peek.dmg" -nobrowse -mountpoint "$MOUNTPOINT" >/dev/null
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - --entitlements "$SIGN_ENTS" "$MOUNTPOINT/Peek.app"
elif [[ "$IDENTITY" == Developer\ ID* ]]; then
  codesign --force --deep --options runtime --sign "$IDENTITY" \
    --entitlements "$SIGN_ENTS" "$MOUNTPOINT/Peek.app"
else
  codesign --force --deep --sign "$IDENTITY" --entitlements "$SIGN_ENTS" "$MOUNTPOINT/Peek.app"
fi
codesign -dv --verbose=2 "$MOUNTPOINT/Peek.app" 2>&1 | egrep 'Authority|TeamIdentifier|Signature=' || true
hdiutil detach "$MOUNTPOINT" >/dev/null
rm -rf "$MOUNTPOINT"
rm -f "$DIST/Peek.dmg"
hdiutil convert "$DIST/rw.Peek.dmg" -format UDZO -imagekey zlib-level=9 -o "$DIST/Peek.dmg" -ov >/dev/null
rm -f "$DIST/rw.Peek.dmg" "$SIGN_ENTS"

cp -f "$DIST/Peek.dmg" "$DIST/Peek-${VERSION}.dmg"
xattr -cr "$DIST/Peek.dmg" "$DIST/Peek-${VERSION}.dmg" || true

echo "Done:"
ls -lh "$DIST/Peek.dmg" "$DIST/Peek-${VERSION}.dmg"
