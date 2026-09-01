#!/usr/bin/env bash
# Download a prebuilt Obscura engine binary for Browsair.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${OBSCURA_VERSION:-v0.2.1}"
ARCH="$(uname -m)"

case "$ARCH" in
  arm64|aarch64) ASSET="obscura-aarch64-macos.tar.gz" ;;
  x86_64)        ASSET="obscura-x86_64-macos.tar.gz" ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

URL="https://github.com/h4ckf0r0day/obscura/releases/download/${VERSION}/${ASSET}"
VENDOR="$ROOT/Vendor/obscura"
BUNDLE_ENGINE="$ROOT/Sources/Browsair/Resources/Engine"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$VENDOR" "$BUNDLE_ENGINE"

echo "Downloading Obscura ${VERSION} (${ASSET})…"
curl -fL --progress-bar -o "$TMP/$ASSET" "$URL"
tar -xzf "$TMP/$ASSET" -C "$TMP"

# Archives usually contain top-level binaries named obscura / obscura-worker.
BIN="$(find "$TMP" -type f -name obscura -perm -111 | head -1)"
WORKER="$(find "$TMP" -type f -name obscura-worker -perm -111 | head -1 || true)"

if [[ -z "${BIN}" ]]; then
  echo "Could not find obscura binary in archive" >&2
  find "$TMP" -maxdepth 3 -type f >&2
  exit 1
fi

cp "$BIN" "$VENDOR/obscura"
chmod +x "$VENDOR/obscura"
cp "$BIN" "$BUNDLE_ENGINE/obscura"
chmod +x "$BUNDLE_ENGINE/obscura"

if [[ -n "${WORKER}" ]]; then
  cp "$WORKER" "$VENDOR/obscura-worker"
  chmod +x "$VENDOR/obscura-worker"
  cp "$WORKER" "$BUNDLE_ENGINE/obscura-worker"
  chmod +x "$BUNDLE_ENGINE/obscura-worker"
fi

echo "${VERSION}" > "$VENDOR/VERSION"
echo "${VERSION}" > "$BUNDLE_ENGINE/VERSION"

echo "Installed:"
ls -lh "$VENDOR/obscura" "$BUNDLE_ENGINE/obscura"
"$VENDOR/obscura" --version 2>/dev/null || "$VENDOR/obscura" --help 2>&1 | head -5 || true
