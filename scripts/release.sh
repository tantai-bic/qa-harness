#!/usr/bin/env bash
# release.sh — patch marketplace name → "qa-harness", bump version, hướng dẫn tag + push.
#
# Usage:  bash scripts/release.sh <new-version>
# Vd:     bash scripts/release.sh 1.0.5
#         bash scripts/release.sh 2.0.0-beta.1
#
# Flow:
#   1. Patch .claude-plugin/marketplace.json  name: "qa-harness-dev" → "qa-harness"
#   2. Bump version trong package.json
#   3. In next steps (git add, commit, tag, push, restore)
#
# Sau khi push xong → chạy: bash scripts/dev-restore.sh

set -euo pipefail

RELEASE_NAME="qa-harness"
MARKETPLACE=".claude-plugin/marketplace.json"

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

# ── Guard: chưa có uncommitted changes trên marketplace ──────────────────────
CURRENT_NAME=$(node -p "require('./$MARKETPLACE').name")
CURRENT_VERSION=$(node -p "require('./package.json').version")

if [[ "$CURRENT_NAME" == "$RELEASE_NAME" ]]; then
  echo "⚠ Marketplace name đã là '$RELEASE_NAME' — có thể đã chạy release.sh trước đó." >&2
  echo "  Nếu muốn tiếp tục: chạy dev-restore.sh trước rồi chạy lại release.sh." >&2
  exit 1
fi

if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
  echo "⚠ Version không đổi ($NEW_VERSION) — chọn version mới hơn." >&2
  exit 1
fi

# ── Patch marketplace name ────────────────────────────────────────────────────
echo "Patching marketplace name: $CURRENT_NAME → $RELEASE_NAME"
node -e "
const fs = require('fs');
const f = '$MARKETPLACE';
const j = JSON.parse(fs.readFileSync(f, 'utf8'));
j.name = '$RELEASE_NAME';
fs.writeFileSync(f, JSON.stringify(j, null, 2) + '\n');
console.log('  ✓', f);
"

# ── Bump version in package.json ─────────────────────────────────────────────
echo "Bumping version: $CURRENT_VERSION → $NEW_VERSION"
node -e "
const fs = require('fs');
const f = 'package.json';
const j = JSON.parse(fs.readFileSync(f, 'utf8'));
j.version = '$NEW_VERSION';
fs.writeFileSync(f, JSON.stringify(j, null, 2) + '\n');
console.log('  ✓', f);
"

echo ""
echo "✓ Ready to release: marketplace.name=$RELEASE_NAME, version=$NEW_VERSION"
echo ""
echo "Next steps:"
echo "  git diff                                        # review trước khi commit"
echo "  git add .claude-plugin/marketplace.json package.json"
echo "  git commit -m \"release: v$NEW_VERSION\""
echo "  git tag v$NEW_VERSION"
echo "  git push && git push origin v$NEW_VERSION"
echo ""
echo "Sau khi push xong:"
echo "  bash scripts/dev-restore.sh                     # revert name về qa-harness-dev"
