#!/usr/bin/env bash
# dev-restore.sh — revert marketplace name → "qa-harness-dev" sau khi release xong.
#
# Usage:  bash scripts/dev-restore.sh
#
# Chạy sau bash scripts/release.sh + git push để branch dev
# quay về đúng @marketplace-name cho consumer test local.

set -euo pipefail

DEV_NAME="qa-harness-dev"
MARKETPLACE=".claude-plugin/marketplace.json"

cd "$(dirname "$0")/.."

CURRENT_NAME=$(node -p "require('./$MARKETPLACE').name")

if [[ "$CURRENT_NAME" == "$DEV_NAME" ]]; then
  echo "✓ Already dev ($DEV_NAME) — nothing to do."
  exit 0
fi

echo "Restoring marketplace name: $CURRENT_NAME → $DEV_NAME"
node -e "
const fs = require('fs');
const f = '$MARKETPLACE';
const j = JSON.parse(fs.readFileSync(f, 'utf8'));
j.name = '$DEV_NAME';
fs.writeFileSync(f, JSON.stringify(j, null, 2) + '\n');
console.log('  ✓', f);
"

echo ""
echo "✓ Restored: marketplace.name=$DEV_NAME"
echo ""
echo "Next steps:"
echo "  git add $MARKETPLACE"
echo "  git commit -m \"chore: restore marketplace name to dev\""
