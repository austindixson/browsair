#!/usr/bin/env bash
#
# One-shot release activation for Browsair.
#
# What it does (in order):
#   1. Verifies gh auth and that a GitHub repo exists (creates one if asked).
#   2. Sets the git origin remote.
#   3. Adds the six release secrets via `gh secret set` (values are read from
#      your local env / files; NOTHING is hardcoded and nothing is printed).
#   4. Commits + tags + pushes.
#
# Run it from a terminal where you can paste secrets — set the env vars below
# first (do NOT put real values in this file; export them in your shell):
#
#   export GITHUB_REPO="ghost64/browsair"          # owner/name
#   export GITHUB_REMOTE_URL="git@github.com:ghost64/browsair.git"
#   export BROWSAIR_SIGN_IDENTITY="Developer ID Application: … (TEAMID)"  # or the 40-char SHA-1
#   export BROWSAIR_CERT_P12_PASSWORD="…export password you chose…"
#   export APPLE_API_KEY_ID="…"                    # App Store Connect Key ID
#   export APPLE_API_ISSUER="…"                    # App Store Connect Issuer ID
#   # Two large binary-ish secrets, provided as FILES (never pasted inline):
#   export BROWSAIR_CERT_P12_PATH="$HOME/secrets/browsair-dev-id.p12"
#   export APPLE_API_KEY_PATH="$HOME/secrets/AuthKey_XXXXXXXXXX.p8"
#
# Then:  bash scripts/setup-release.sh
#
# gh reads a secret from stdin, so `gh secret set NAME < file` (or <<< "$VAL")
# is used throughout — no secret ever lands in this script or in your shell
# history as an argument.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Browsair/Resources/Info.plist)"
TAG="v${VERSION}"

need() { [[ -n "${!1:-}" ]] || { echo "ERROR: required env var $1 is not set." >&2; exit 1; }; }

echo "== Preflight =="
command -v gh >/dev/null || { echo "ERROR: gh CLI not installed." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "ERROR: not authenticated. Run: gh auth login" >&2; exit 1; }

need GITHUB_REPO
need GITHUB_REMOTE_URL
need BROWSAIR_SIGN_IDENTITY
need BROWSAIR_CERT_P12_PASSWORD
need APPLE_API_KEY_ID
need APPLE_API_ISSUER
need BROWSAIR_CERT_P12_PATH
need APPLE_API_KEY_PATH
[[ -f "$BROWSAIR_CERT_P12_PATH" ]] || { echo "ERROR: cert p12 not found at $BROWSAIR_CERT_P12_PATH" >&2; exit 1; }
[[ -f "$APPLE_API_KEY_PATH" ]]     || { echo "ERROR: API key p8 not found at $APPLE_API_KEY_PATH" >&2; exit 1; }

# Ensure the remote repo exists (create private unless you set CREATE_PUBLIC=1).
if ! gh repo view "$GITHUB_REPO" >/dev/null 2>&1; then
  echo "Repo $GITHUB_REPO not found — creating it."
  if [[ "${CREATE_PUBLIC:-0}" == "1" ]]; then
    gh repo create "$GITHUB_REPO" --public
  else
    gh repo create "$GITHUB_REPO" --private
  fi
fi

echo "== Set origin =="
if git remote get-url origin >/dev/null 2>&1; then
  echo "origin exists -> $(git remote get-url origin); leaving as-is. (git remote set-url origin \"$GITHUB_REMOTE_URL\" to change.)"
else
  git remote add origin "$GITHUB_REMOTE_URL"
  echo "origin -> $GITHUB_REMOTE_URL"
fi

echo "== Add secrets (values never echoed) =="
# Small string secrets come from env; the two binaries are piped from file.
printf '%s' "$BROWSAIR_SIGN_IDENTITY"       | gh secret set BROWSAIR_SIGN_IDENTITY       --repo "$GITHUB_REPO"
printf '%s' "$BROWSAIR_CERT_P12_PASSWORD"   | gh secret set BROWSAIR_CERT_P12_PASSWORD   --repo "$GITHUB_REPO"
printf '%s' "$APPLE_API_KEY_ID"             | gh secret set APPLE_API_KEY_ID             --repo "$GITHUB_REPO"
printf '%s' "$APPLE_API_ISSUER"             | gh secret set APPLE_API_ISSUER             --repo "$GITHUB_REPO"
gh secret set BROWSAIR_CERT_P12_BASE64 --repo "$GITHUB_REPO" < <(base64 -i "$BROWSAIR_CERT_P12_PATH")
gh secret set APPLE_API_KEY            --repo "$GITHUB_REPO" < "$APPLE_API_KEY_PATH"
echo "Secrets set. Confirm with: gh secret list --repo $GITHUB_REPO"

echo "== Commit, tag, push =="
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree has uncommitted changes — commit them first (this script won't guess a commit message)." >&2
  exit 1
fi
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "Tag $TAG already exists locally."
else
  git tag "$TAG"
  echo "Created tag $TAG"
fi
git push origin "$TAG"   # triggers the Release workflow (signs + notarizes)
echo "Done. Watch it with:  gh run watch --repo $GITHUB_REPO"
