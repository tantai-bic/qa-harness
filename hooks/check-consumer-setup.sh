#!/bin/bash
# SessionStart hook: check consumer đã setup các folder/file bắt buộc chưa.
#
# Khi consumer install plugin lần đầu, missing nhiều setup → hook nhắc trong
# session đầu tiên (matcher=startup). KHÔNG fire khi resume/clear/compact để
# tránh nhiễu.
#
# Default required paths:
#   _bmad/bmm/config.yaml                     BMAD config (user_name, language)
#   docs/roadmap/README.md                    Roadmap index (cho enforce-roadmap-reading)
#   docs/templates/log-bug-api-template.md    Bug log template
#   package.json                              Project manifest
#   playwright.config.ts|.js                  Playwright config
#   src/constants/api.constants.ts            Endpoints
#   src/fixtures/                             Fixture dir
#   tests/                                    Test dir
#
# Consumer customization:
#   - Bổ sung paths qua env CONSUMER_REQUIRED_PATHS (newline-separated, support
#     relative path + glob alternation via "|").
#       Vd: CONSUMER_REQUIRED_PATHS=$'docs/api/\ntsconfig.json'
#   - Loại bỏ default paths qua CONSUMER_SETUP_SKIP_DEFAULTS=1
#   - Bypass: SKIP_SETUP_CHECK=1 hoặc SKIP_HOOKS=1
#
# Per CLAUDE.md: node -e (jq không có trên Windows Git Bash).

set -uo pipefail

SPAN_HOOK_NAME="check-consumer-setup"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_SETUP_CHECK:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_SETUP_CHECK"
  exit 0
fi

# Only fire on cold startup — skip resume/clear/compact để tránh remind lặp
SOURCE=$(node -e '
try {
  const i = JSON.parse(require("fs").readFileSync(0, "utf-8"));
  process.stdout.write(i.source || "");
} catch { process.exit(0); }
' <<< "$INPUT" 2>/dev/null)

if [[ "$SOURCE" != "startup" ]]; then
  SPAN_DECISION="skip"
  SPAN_DETAIL="source=$SOURCE"
  exit 0
fi

# Self-detection: nếu đang chạy trên plugin source itself (có
# .claude-plugin/plugin.json với "bmad-harness-plugin" name) → skip.
# Plugin source không cần check consumer setup cho chính nó.
if [[ -f ".claude-plugin/plugin.json" ]]; then
  if grep -q '"name"[[:space:]]*:[[:space:]]*"bmad-harness-plugin"' .claude-plugin/plugin.json 2>/dev/null; then
    SPAN_DECISION="skip"
    SPAN_DETAIL="plugin-self"
    exit 0
  fi
fi

# ─── Build required paths list ──────────────────────────────────────────────
DEFAULT_PATHS=(
  "_bmad/bmm/config.yaml|BMAD config|consumer phải set project_name, user_name, communication_language"
  "docs/roadmap/README.md|Roadmap index|cần cho enforce-roadmap-reading hook discovery"
  "docs/templates/log-bug-api-template.md|Bug log template|cho hierarchy of truth — log BE bug, không sửa test"
  "package.json|NPM manifest|Playwright + TS dependencies"
  "playwright.config.ts|playwright.config.js|Playwright config|timeouts, projects, retries"
  "src/constants/api.constants.ts|API_ENDPOINTS|endpoint constants — KHÔNG hardcode URL"
  "src/fixtures|Fixture dir|auto-cleanup fixtures (Rule 4a — import test từ @src/fixtures)"
  "tests|Test dir|tests/api/, tests/e2e/"
)

MISSING_JSON=$(node -e '
const fs = require("fs");
const path = require("path");

const defaults = process.env.CONSUMER_SETUP_SKIP_DEFAULTS === "1" ? [] :
  process.argv.slice(1);
const extras = (process.env.CONSUMER_REQUIRED_PATHS || "")
  .split(/\r?\n/).map(s => s.trim()).filter(Boolean);

const all = [...defaults, ...extras.map(p => p + "|(custom path)|consumer-defined")];
const missing = [];

for (const entry of all) {
  const parts = entry.split("|");
  // Format 1: "path|label|desc" → 3 parts
  // Format 2: "pathA|pathB|label|desc" → 4 parts (alternation, accept either)
  let candidates, label, desc;
  if (parts.length >= 4) {
    candidates = [parts[0], parts[1]];
    label = parts[2];
    desc  = parts[3];
  } else {
    candidates = [parts[0]];
    label = parts[1] || parts[0];
    desc  = parts[2] || "";
  }
  const found = candidates.some(c => {
    try { return fs.existsSync(path.resolve(process.cwd(), c)); } catch { return false; }
  });
  if (!found) missing.push({ candidates, label, desc });
}

process.stdout.write(JSON.stringify(missing));
' "${DEFAULT_PATHS[@]}" 2>/dev/null)

MISSING_COUNT=$(node -e '
const m = JSON.parse(process.argv[1] || "[]");
process.stdout.write(String(m.length));
' "$MISSING_JSON" 2>/dev/null)

if [[ "${MISSING_COUNT:-0}" == "0" ]]; then
  SPAN_DECISION="skip"
  SPAN_DETAIL="all-paths-present"
  exit 0
fi

# ─── Emit additionalContext JSON ────────────────────────────────────────────
OUT=$(node -e '
const missing = JSON.parse(process.argv[1] || "[]");
const items = missing.map((m, i) => {
  const pathStr = m.candidates.length > 1
    ? m.candidates.map(c => "`" + c + "`").join(" hoặc ")
    : "`" + m.candidates[0] + "`";
  return "  " + (i+1) + ". " + pathStr + " — " + m.label + "\n     " + (m.desc || "");
}).join("\n");

const lines = [
  "🛠️  CONSUMER SETUP CHECK — phát hiện " + missing.length + " path bắt buộc chưa tồn tại.",
  "",
  "Plugin bmad-harness-plugin yêu cầu consumer setup các path sau để hooks/skills hoạt động đầy đủ:",
  "",
  items,
  "",
  "═══ Hướng dẫn ═══",
  "  • Tạo các path trên (file/folder) — ưu tiên cái critical (BMAD config, package.json, playwright.config)",
  "  • Tham khảo template structure ở skills/qa-engineer/architecture.md § 10 Directory Structure",
  "  • Sau khi tạo xong, restart session để hook re-check",
  "",
  "Mỗi path missing làm 1 capability bị degrade:",
  "  • _bmad/bmm/config.yaml         → BMAD agents activation fail (load config error)",
  "  • docs/roadmap/                 → enforce-roadmap-reading hook silent (no roadmap to suggest)",
  "  • src/constants/api.constants.ts → test code vi phạm Rule: hardcode URL",
  "  • src/fixtures/                 → spec không import được @src/fixtures (Rule 4a)",
  "",
  "Bypass: SKIP_SETUP_CHECK=1 (per-hook) hoặc SKIP_HOOKS=1 (master).",
  "Tuỳ biến: CONSUMER_REQUIRED_PATHS (newline) thêm path; CONSUMER_SETUP_SKIP_DEFAULTS=1 bỏ defaults.",
].join("\n");

const out = {
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: lines
  }
};
process.stdout.write(JSON.stringify(out));
' "$MISSING_JSON")

printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="missing=$MISSING_COUNT"

exit 0
