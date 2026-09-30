#!/usr/bin/env bash
# Static site server for Browsair landing page (Railway).
# Serves everything under ./public with correct MIME types, binding $PORT.
set -euo pipefail
cd "$(dirname "$0")/public"
exec python3 -m http.server "${PORT:-8080}" --bind 0.0.0.0
