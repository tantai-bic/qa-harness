#!/usr/bin/env bash
# pack.sh — bundle marketplace (root + plugins/) thành tarball để distribute manually.
#
# Output: dist/<name>-<version>.tgz (gzip tar) — name/version từ package.json
# Exclude: node_modules, dist, .git, runtime cache, session-logs, .env, _bmad-output
#
# Usage: bash scripts/pack.sh
# Hoặc:  npm run pack

set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f .claude-plugin/marketplace.json ]]; then
  echo "❌ Không tìm thấy .claude-plugin/marketplace.json — run từ marketplace root." >&2
  exit 1
fi

if [[ ! -f package.json ]]; then
  echo "❌ Không tìm thấy package.json — cần cho name + version." >&2
  exit 1
fi

VERSION=$(node -p "require('./package.json').version")
NAME=$(node -p "require('./package.json').name")
OUT="dist/${NAME}-${VERSION}.tgz"

mkdir -p dist

# Tar exclude list — runtime state + dev artifact + secrets
EXCLUDES=(
  --exclude='./node_modules'
  --exclude='./dist'
  --exclude='./.git'
  --exclude='./.github'
  --exclude='./.husky/_'
  --exclude='./.claude/session-logs'
  --exclude='./.claude/hooks/.langfuse-queue'
  --exclude='./.claude/hooks/.langfuse-cursor'
  --exclude='./.claude/hooks/.session-map'
  --exclude='./.claude/hooks/.hook-spans-pending'
  --exclude='./.claude/hooks/.current-log'
  --exclude='./.claude/hooks/.claude'
  --exclude='./.claude/settings.local.json'
  --exclude='./_bmad-output'
  --exclude='./test-results'
  --exclude='./playwright-report'
  --exclude='./.env'
  --exclude='./.env.local'
  --exclude='./*.tgz'
  --exclude='./.DS_Store'
  --exclude='*.log'
)

echo "📦 Packing $NAME v$VERSION → $OUT"
tar "${EXCLUDES[@]}" -czf "$OUT" .

SIZE=$(du -h "$OUT" | cut -f1)
FILES=$(tar -tzf "$OUT" | wc -l)

echo ""
echo "✓ Done"
echo "  File:  $OUT"
echo "  Size:  $SIZE"
echo "  Files: $FILES"
echo ""
echo "Install consumer-side:"
echo "  1. Extract: tar -xzf $OUT -C /path/to/$NAME"
echo "  2. Add marketplace vào ~/.claude/settings.json:"
echo "       \"extraKnownMarketplaces\": { \"$NAME\": { \"type\": \"local\", \"path\": \"/path/to/$NAME\" } }"
echo "  3. Enable plugins:"
echo "       \"enabledPlugins\": { \"bmad-workflows@$NAME\": true, ... }"
