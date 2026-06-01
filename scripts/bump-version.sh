#!/usr/bin/env bash
# bump-version.sh — bump marketplace bundle version trong package.json.
#
# Source of truth: package.json (release artifact name + tag verification dùng nó).
# Per-plugin version (plugins/*/.claude-plugin/plugin.json) bump độc lập — không cascade ở đây.
#
# Usage:  bash scripts/bump-version.sh <new-version>
# Vd:     bash scripts/bump-version.sh 1.0.3
#         bash scripts/bump-version.sh 2.0.0-beta.1   ← prerelease (tag chứa `-`)
#
# Sau bump → commit → tag → push → GitHub Action auto-build release.

set -euo pipefail

NEW="${1:-}"
if [[ -z "$NEW" ]]; then
  echo "❌ Missing version argument." >&2
  echo "Usage: bash scripts/bump-version.sh <new-version>" >&2
  echo "Vd:    bash scripts/bump-version.sh 1.0.3" >&2
  exit 1
fi

# Semver basic validate (X.Y.Z [-prerelease])
if [[ ! "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
  echo "❌ Invalid semver: $NEW (expect X.Y.Z hoặc X.Y.Z-prerelease)" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

if [[ ! -f package.json ]]; then
  echo "❌ Không tìm thấy package.json." >&2
  exit 1
fi

CURRENT=$(node -p "require('./package.json').version")
echo "Current: $CURRENT"
echo "New:     $NEW"

if [[ "$CURRENT" == "$NEW" ]]; then
  echo "⚠ Version unchanged — exit." >&2
  exit 1
fi

node -e "
const fs = require('fs');
const NEW = process.argv[1];
const f = 'package.json';
const j = JSON.parse(fs.readFileSync(f, 'utf8'));
j.version = NEW;
fs.writeFileSync(f, JSON.stringify(j, null, 2) + '\n');
console.log('  ✓', f);
" "$NEW"

echo ""
echo "✓ Version bumped: $CURRENT → $NEW"
echo ""
echo "Next steps:"
echo "  git diff package.json          # review"
echo "  git add package.json"
echo "  git commit -m \"Bump version to $NEW\""
echo "  git tag v$NEW"
echo "  git push && git push origin v$NEW"
echo ""
echo "GitHub Action sẽ tự build + create release."
echo ""
echo "Note: muốn bump version 1 plugin riêng (vd bmad-workflows 1.1.0 → 1.2.0):"
echo "  sửa thủ công plugins/<name>/.claude-plugin/plugin.json — không liên quan tag/release."
