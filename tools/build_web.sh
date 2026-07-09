#!/usr/bin/env bash
#
# build_web.sh — LOVE.js 웹 빌드 파이프라인
#
# Usage:
#   cd /path/to/ProjectR
#   bash tools/build_web.sh
#
# Prerequisites:
#   - Node.js (for npx / love.js)
#
# What it does:
#   1. Creates a .love archive of the project
#   2. Runs love.js (via npx) to generate the web bundle
#   3. Output goes to build/web/
#
# Output:
#   build/web/index.html
#   build/web/love.js
#   build/web/love.wasm
#   build/web/projectr.love
#

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build/web"
LOVE_FILE="$BUILD_DIR/projectr.love"

echo "==> 1/3: Preparing build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> 2/3: Packaging .love file..."
cd "$PROJECT_ROOT"
zip -r "$LOVE_FILE" . \
  -x ".git/*" \
  -x "build/*" \
  -x "node_modules/*" \
  -x "server/*" \
  -x "spec/*" \
  -x "tools/*" \
  -x "*.md"

echo "==> 3/3: Generating web bundle with love.js..."

# Use locally installed love.js via npx
# --title is required to avoid interactive prompt
npx --no-install love.js --compatibility --title 'ProjectR' "$LOVE_FILE" "$BUILD_DIR"

echo ""
echo "Web build complete → build/web/"
echo "  Serve with:  python3 -m http.server 3100 -d build/web/"
echo "  Open at:     http://127.0.0.1:3100"
