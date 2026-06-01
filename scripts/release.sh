#!/usr/bin/env bash
# release.sh — build release artifact với marketplace name "qa-harness".
#
# Source code KHÔNG bị sửa: .claude-plugin/marketplace.json giữ nguyên "qa-harness-dev".
# Script copy sang .release/ (temp), patch tên ở đó, pack → dist/qa-harness-<version>.tgz.
#
# Usage:  bash scripts/release.sh <new-version>
# Vd:     bash scripts/release.sh 1.0.5
#         bash scripts/release.sh 2.0.0-beta.1
#
# Flow:
#   1. Validate version arg
#   2. Bump version trong package.json (source — cần cho git tag tracking)
#   3. Copy source → .release/ temp dir
#   4. Patch .release/.claude-plugin/marketplace.json name → "qa-harness"
#   5. Pack từ .release/ → dist/qa-harness-<version>.tgz
#   6. Cleanup .release/
#   7. In next steps (commit, tag, push, upload asset)

set -euo pipefail

RELEASE_NAME="qa-harness"
RELEASE_DIR=".release"

cd "$(dirname "$0")/.."

# ── Validate version arg ──────────────────────────────────────────────────────
NEW_VERSION="${1:-}"
if [[ -z "$NEW_VERSION" ]]; then
  echo "❌ Missing version argument." >&2
  echo "Usage: bash scripts/release.sh <version>" >&2
  echo "Vd:    bash scripts/release.sh 1.0.5" >&2
  exit 1
fi

if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
  echo "❌ Invalid semver: $NEW_VERSION (expect X.Y.Z hoặc X.Y.Z-prerelease)" >&2
  exit 1
fi

CURRENT_VERSION=$(node -p "require('./package.json').version")
if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
  echo "⚠ Version không đổi ($NEW_VERSION) — chọn version mới hơn." >&2
  exit 1
fi

# ── Bump version trong package.json (source) ─────────────────────────────────
echo "Bumping version: $CURRENT_VERSION → $NEW_VERSION"
node -e "
const fs = require('fs');
const f = 'package.json';
const j = JSON.parse(fs.readFileSync(f, 'utf8'));
j.version = '$NEW_VERSION';
fs.writeFileSync(f, JSON.stringify(j, null, 2) + '\n');
console.log('  ✓', f);
"

# ── Build release artifact trong temp dir ────────────────────────────────────
echo "Building release artifact in $RELEASE_DIR/ ..."
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Copy chỉ những gì cần thiết cho consumer
cp -r .claude-plugin "$RELEASE_DIR/"
cp -r plugins        "$RELEASE_DIR/"
cp    package.json   "$RELEASE_DIR/"
[[ -f README.md  ]] && cp README.md  "$RELEASE_DIR/" || true
[[ -f .mcp.json  ]] && cp .mcp.json  "$RELEASE_DIR/" || true

# Patch marketplace name trong artifact (KHÔNG ảnh hưởng source)
SOURCE_NAME=$(node -p "require('./.claude-plugin/marketplace.json').name")
echo "Patching artifact name: $SOURCE_NAME → $RELEASE_NAME"
node -e "
const fs = require('fs');
const f = '$RELEASE_DIR/.claude-plugin/marketplace.json';
const j = JSON.parse(fs.readFileSync(f, 'utf8'));
j.name = '$RELEASE_NAME';
fs.writeFileSync(f, JSON.stringify(j, null, 2) + '\n');
console.log('  ✓', f, '(artifact only — source unchanged)');
"

# ── Pack từ release dir ───────────────────────────────────────────────────────
mkdir -p dist
OUT="dist/${RELEASE_NAME}-${NEW_VERSION}.tgz"
tar -czf "$OUT" -C "$RELEASE_DIR" .

# ── Cleanup temp dir ──────────────────────────────────────────────────────────
rm -rf "$RELEASE_DIR"

SIZE=$(du -h "$OUT" | cut -f1)
echo ""
echo "✓ Release artifact built:"
echo "  File:             $OUT ($SIZE)"
echo "  marketplace.name: $RELEASE_NAME (patched in artifact)"
echo "  version:          $NEW_VERSION"
echo "  Source:           .claude-plugin/marketplace.json KHÔNG bị sửa (still '$SOURCE_NAME')"
echo ""
echo "Next steps:"
echo "  git add package.json"
echo "  git commit -m \"Bump version to $NEW_VERSION\""
echo "  git tag v$NEW_VERSION"
echo "  git push && git push origin v$NEW_VERSION"
echo "  # Upload $OUT làm GitHub release asset"
