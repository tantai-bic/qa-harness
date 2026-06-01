#!/bin/bash
# SessionStart hook: check qa-context-specific consumer setup.
# Checks: docs/roadmap/README.md (enforce-roadmap-reading hook cần)
# Bypass: SKIP_SETUP_CHECK=1 | SKIP_HOOKS=1

set -uo pipefail

SPAN_HOOK_NAME="qa-context-check-setup"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_SETUP_CHECK:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_SETUP_CHECK"
  exit 0
fi

SOURCE=$(node -e '
try { process.stdout.write(JSON.parse(require("fs").readFileSync(0,"utf-8")).source||""); }
catch { process.exit(0); }
' <<< "$INPUT" 2>/dev/null)
[[ "$SOURCE" != "startup" ]] && { SPAN_DECISION="skip"; SPAN_DETAIL="source=$SOURCE"; exit 0; }

[[ -f ".claude-plugin/marketplace.json" ]] && { SPAN_DECISION="skip"; SPAN_DETAIL="plugin-self"; exit 0; }

# ─── Check docs/roadmap/README.md ───────────────────────────────────────────
if [[ -e "docs/roadmap/README.md" ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="all-pass"; exit 0
fi

OUT=$(node -e '
const out = {
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: [
      "📋 [qa-context] SETUP CHECK — 1 mục chưa có:\n",
      "  1. \`docs/roadmap/README.md\` — index cho enforce-roadmap-reading hook\n",
      "Ảnh hưởng: enforce-roadmap-reading.sh silent — hook không tìm được roadmap để inject vào prompt.",
      "Fix: tạo docs/roadmap/ và thêm README.md index các file roadmap của project.",
      "",
      "Bypass: SKIP_SETUP_CHECK=1"
    ].join("\n")
  }
};
process.stdout.write(JSON.stringify(out));
')

printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="missing=docs/roadmap"
exit 0
