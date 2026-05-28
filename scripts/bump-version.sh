#!/usr/bin/env bash
# bump-version.sh — đồng bộ version qua 3 file metadata:
#   - .claude-plugin/plugin.json       (top-level version)
#   - .claude-plugin/marketplace.json  (metadata.version + plugins[].version)
#   - package.json                     (version)
#
# Usage:  bash scripts/bump-version.sh <new-version>
# Vd:     bash scripts/bump-version.sh 1.1.0
#         bash scripts/bump-version.sh 2.0.0-beta.1   ← sẽ thành prerelease
#
# Sau bump → commit → tag → push → GitHub Action auto-build release.

set -euo pipefail

NEW="${1:-}"
if [[ -z "$NEW" ]]; then
  echo "❌ Missing version argument." >&2
  echo "Usage: bash scripts/bump-version.sh <new-version>" >&2
  echo "Vd:    bash scripts/bump-version.sh 1.1.0" >&2
  exit 1
fi

# Semver basic validate (X.Y.Z [-prerelease])
if [[ ! "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$ ]]; then
  echo "❌ Invalid semver: $NEW (expect X.Y.Z hoặc X.Y.Z-prerelease)" >&2
  exit 1
fi

cd "$(dirname "$0")/.."

CURRENT=$(node -p "require('./.claude-plugin/plugin.json').version")
echo "Current: $CURRENT"
echo "New:     $NEW"

if [[ "$CURRENT" == "$NEW" ]]; then
  echo "⚠ Version unchanged — exit." >&2
  exit 1
fi

# Bump 3 files atomically via node
node -e "
const fs = require('fs');
const NEW = process.argv[1];
const files = [
  '.claude-plugin/plugin.json',
  '.claude-plugin/marketplace.json',
  'package.json',
];
for (const f of files) {
  const j = JSON.parse(fs.readFileSync(f, 'utf8'));
  if (j.version !== undefined) j.version = NEW;
  if (j.metadata && j.metadata.version !== undefined) j.metadata.version = NEW;
  if (Array.isArray(j.plugins)) j.plugins.forEach(p => { if (p.version !== undefined) p.version = NEW; });
  fs.writeFileSync(f, JSON.stringify(j, null, 2) + '\n');
  console.log('  ✓', f);
}
" "$NEW"

echo ""
echo "✓ Version bumped: $CURRENT → $NEW"
echo ""
echo "Next steps:"
echo "  git diff                                 # review changes"
echo "  git add .claude-plugin/ package.json"
echo "  git commit -m \"Bump version to $NEW\""
echo "  git tag v$NEW"
echo "  git push && git push origin v$NEW"
echo ""
echo "GitHub Action sẽ tự build + create release."
