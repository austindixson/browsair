#!/usr/bin/env bash
#
# Package Browsair into a signed (and optionally notarized + stapled) DMG.
#
# PR 3.1 — real signing. Replaces the old ad-hoc signature with the
# Developer ID Application identity + hardened runtime. The DMG version is
# read from Info.plist instead of a hardcoded string.
#
# Identity resolution (first match wins):
#   1. $BROWSAIR_SIGN_IDENTITY  (a Developer ID Application SHA-1 or name)
#   2. Auto-detected from `security find-identity -p codesigning` when exactly
#      one "Developer ID Application" identity is installed.
#   3. Ad-hoc ("-" or "Apple Development") — only if ALLOW_ADHOC=1. Otherwise
#      the script refuses, because an ad-hoc build is not shippable (it churns
#      on every rebuild and breaks the com.browsair.ai Keychain ACL — audit R4).
#
# Notarization runs only when NOTARIZE=1 AND credentials are available.
# Provide credentials in one of these ways (see `notarytool store-credentials`):
#   * a stored keychain profile:  NOTARY_PROFILE=<name>
#   * App Store Connect API key:  APPLE_API_KEY=<.p8 path> APPLE_API_KEY_ID=<id> APPLE_API_ISSUER=<issuer uuid>
#   * Apple ID + app-specific pw: APPLE_ID=<email> APPLE_APP_SPECIFIC_PASSWORD=<pw> APPLE_TEAM_ID=<team>
# Set SKIP_NOTARIZE=1 to build a Developer-ID-signed (not stapled) DMG offline.
#
# Usage: scripts/package-dmg.sh [1024x1024-icon.png]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Browsair.app"
STAGE="$DIST/dmg-root"
ICON_SRC="${1:-}"
BUILD="$ROOT/.build/release"
ENTITLEMENTS="$ROOT/Sources/Browsair/Resources/Browsair.entitlements"
PLIST="$ROOT/Sources/Browsair/Resources/Info.plist"

cd "$ROOT"

plist_get() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }

# --- Resolve version + bundle id from Info.plist (kills hardcoded 0.2.0) ----
VERSION="$(plist_get CFBundleShortVersionString)"
BUILD_NUM="$(plist_get CFBundleVersion)"
[[ -n "$VERSION" && -n "$BUILD_NUM" ]] || { echo "Could not read version from $PLIST" >&2; exit 1; }
echo "Version from Info.plist: $VERSION (build $BUILD_NUM)"

# --- Icon -------------------------------------------------------------------
if [[ -z "$ICON_SRC" ]]; then
  for candidate in \
    "$ROOT/Sources/Browsair/Resources/AppIcon.png" \
    "$ROOT/Design/AppIcon.png"
  do
    if [[ -f "$candidate" ]]; then ICON_SRC="$candidate"; break; fi
  done
fi
if [[ -z "$ICON_SRC" || ! -f "$ICON_SRC" ]]; then
  echo "No app icon PNG found. Pass a 1024x1024 image as the first argument." >&2
  exit 1
fi

# --- Resolve signing identity ----------------------------------------------
resolve_identity() {
  if [[ -n "${BROWSAIR_SIGN_IDENTITY:-}" ]]; then
    echo "$BROWSAIR_SIGN_IDENTITY"; return 0
  fi
  # Auto-detect: Developer ID Application identities, name lines only.
  local lines
  lines="$(security find-identity -p codesigning -v 2>/dev/null \
    | sed -nE 's/^ *[0-9]+\) ([0-9A-Fa-f]+) "(Developer ID Application: .*)"$/\1\t\2/p')"
  local count
  count="$(printf '%s' "$lines" | grep -c . || true)"
  if [[ "$count" -eq 1 ]]; then
    printf '%s' "$lines" | cut -f1
  elif [[ "$count" -gt 1 ]]; then
    {
      echo "Multiple Developer ID Application identities found. Set BROWSAIR_SIGN_IDENTITY to one SHA-1:"
      printf '%s\n' "$lines" | cut -f1,2
    } >&2
    return 1
  else
    return 1
  fi
}

SIGN_IDENTITY=""
if SIGN_IDENTITY="$(resolve_identity)"; then
  echo "Signing identity: $SIGN_IDENTITY"
else
  if [[ "${ALLOW_ADHOC:-0}" == "1" ]]; then
    SIGN_IDENTITY="-"
    echo "WARNING: no Developer ID Application identity found; using AD-HOC signature (not shippable)." >&2
  else
    cat >&2 <<'EOF'
ERROR: no usable "Developer ID Application" identity found in the keychain.

  Install / import the Developer ID cert + private key, or set
  BROWSAIR_SIGN_IDENTITY=<SHA-1 or full name>, or re-run with ALLOW_ADHOC=1
  for a local (non-shippable) ad-hoc build.

  List what is installed with:
    security find-identity -p codesigning -v
EOF
    exit 1
  fi
fi

# Hardened runtime only applies to a real Developer ID signature.
CODESIGN_OPTS=(--force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" --timestamp)
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  CODESIGN_OPTS+=(--options runtime)
fi

# --- Build ------------------------------------------------------------------
echo "Building release..."
swift build -c release --product Browsair

mkdir -p "$DIST"
rm -rf "$APP" "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Assembling app bundle..."
cp "$BUILD/Browsair" "$APP/Contents/MacOS/Browsair"
chmod +x "$APP/Contents/MacOS/Browsair"
if [[ -d "$BUILD/Browsair_Browsair.bundle" ]]; then
  cp -R "$BUILD/Browsair_Browsair.bundle" "$APP/Contents/Resources/Browsair_Browsair.bundle"
fi
cp "$PLIST" "$APP/Contents/Info.plist"

# Regenerate the icon (writes back into the tracked Resources/ so the bundle
# icon and SwiftPM's excluded copy stay in sync with the supplied source).
echo "Making AppIcon.icns from ${ICON_SRC}"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
MASTER="$DIST/AppIcon-1024.png"
sips -s format png "$ICON_SRC" --out "$MASTER" >/dev/null
sips -z 16 16     "$MASTER" --out "$ICONSET/icon_16x16.png"       >/dev/null
sips -z 32 32     "$MASTER" --out "$ICONSET/icon_16x16@2x.png"    >/dev/null
sips -z 32 32     "$MASTER" --out "$ICONSET/icon_32x32.png"       >/dev/null
sips -z 64 64     "$MASTER" --out "$ICONSET/icon_32x32@2x.png"    >/dev/null
sips -z 128 128   "$MASTER" --out "$ICONSET/icon_128x128.png"     >/dev/null
sips -z 256 256   "$MASTER" --out "$ICONSET/icon_128x128@2x.png"  >/dev/null
sips -z 256 256   "$MASTER" --out "$ICONSET/icon_256x256.png"     >/dev/null
sips -z 512 512   "$MASTER" --out "$ICONSET/icon_256x256@2x.png"  >/dev/null
sips -z 512 512   "$MASTER" --out "$ICONSET/icon_512x512.png"     >/dev/null
sips -z 1024 1024 "$MASTER" --out "$ICONSET/icon_512x512@2x.png"  >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$MASTER" "$ROOT/Sources/Browsair/Resources/AppIcon.png"
cp "$APP/Contents/Resources/AppIcon.icns" "$ROOT/Sources/Browsair/Resources/AppIcon.icns"

# --- Sign -------------------------------------------------------------------
echo "Signing app bundle (Developer ID + hardened runtime)..."
[[ -f "$ENTITLEMENTS" ]] || { echo "Missing entitlements: $ENTITLEMENTS" >&2; exit 1; }
# Sign nested resources first (bundle has no Mach-O helpers today, but be safe),
# then the executable, then the bundle — deepest-first, one final bundle sig.
if [[ -d "$APP/Contents/Resources/Browsair_Browsair.bundle" ]]; then
  codesign "${CODESIGN_OPTS[@]}" "$APP/Contents/Resources/Browsair_Browsair.bundle"
fi
codesign "${CODESIGN_OPTS[@]}" "$APP/Contents/MacOS/Browsair"
codesign "${CODESIGN_OPTS[@]}" "$APP"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP"
echo "--- codesign -dvv ---"
codesign -dvv "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier|flags|Runtime' || true

# --- Build + (optional) notarize the DMG ------------------------------------
echo "Creating DMG..."
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Browsair.app"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/Browsair-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Browsair" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
# Sign the container itself so the DMG is a valid signed artifact.
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

have_notary_creds() {
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then return 0; fi
  if [[ -n "${APPLE_API_KEY:-}" && -n "${APPLE_API_KEY_ID:-}" && -n "${APPLE_API_ISSUER:-}" ]]; then return 0; fi
  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then return 0; fi
  return 1
}

notary_args() {
  # Emits one argument per line; callers read them into an array.
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    printf '%s\n' --keychain-profile "$NOTARY_PROFILE"
  elif [[ -n "${APPLE_API_KEY:-}" ]]; then
    printf '%s\n' --api-key "$APPLE_API_KEY" --api-key-id "$APPLE_API_KEY_ID" --api-issuer "$APPLE_API_ISSUER"
  else
    printf '%s\n' --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID"
  fi
}

if [[ "${SKIP_NOTARIZE:-0}" == "1" ]]; then
  echo "NOTARIZE: skipped (SKIP_NOTARIZE=1) — artifact is Developer-ID-signed but NOT stapled."
elif [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "NOTARIZE: skipped (ad-hoc build cannot be notarized)."
elif [[ "${NOTARIZE:-0}" == "1" ]]; then
  if ! have_notary_creds; then
    cat >&2 <<'EOF'
NOTARIZE=1 but no notarization credentials found. Provide ONE of:
  NOTARY_PROFILE=<stored profile>          (notarytool store-credentials)
  APPLE_API_KEY=<.p8> APPLE_API_KEY_ID=<id> APPLE_API_ISSUER=<uuid>
  APPLE_ID=<email> APPLE_APP_SPECIFIC_PASSWORD=<pw> APPLE_TEAM_ID=<team>
Building signed-but-unnotarized DMG instead.
EOF
  else
    # Read the args into an array (print -r -- emits one arg per line).
    NOTARY_CRED_ARGS=()
    while IFS= read -r line; do NOTARY_CRED_ARGS+=("$line"); done < <(notary_args)
    echo "Submitting to Apple notarization (this can take several minutes)..."
    xcrun notarytool submit "$DMG" "${NOTARY_CRED_ARGS[@]}" --wait
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
  fi
else
  echo "NOTARIZE: not requested (set NOTARIZE=1 to submit + staple)."
fi

# --- spctl acceptance gate --------------------------------------------------
# Gate only when the artifact is Developer-ID-signed. Assessment (spctl) needs
# the app installed or a stapled ticket, so run it against the installed-style
# bundle and report (do not hard-fail) — a notarized+stapled build accepts.
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  echo "--- spctl assessment ---"
  spctl --assess --type execute --verbose=2 "$APP" 2>&1 || \
    echo "(spctl did not accept the un-installed bundle; expected until the app is in /Applications or notarization is stapled)"
fi

echo "Built:"
ls -lh "$APP/Contents/MacOS/Browsair" "$DMG"
echo "$DMG"
