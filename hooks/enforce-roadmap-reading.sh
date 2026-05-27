#!/bin/bash
# UserPromptSubmit hook: nhắc Claude đọc docs/roadmap/ (nếu consumer có) trước khi
# implement/sửa code/viết test cho feature mới.
#
# Generic, project-agnostic. KHÔNG hardcode tên phase/domain của consumer cụ thể —
# chỉ trigger khi prompt có signal viết test/implement, sau đó liệt kê các roadmap
# doc đang tồn tại để Claude đọc theo upstream chain mà consumer tự define.
#
# Trigger keywords (case-insensitive):
#   - VN: tính năng, làm tính năng, implement, viết test, tạo test, scaffold
#   - EN: implement, build feature, write test, create test, test plan, spec
#   - Path: tests/api, tests/e2e, src/, .local/test-hooks
#   - Generic: roadmap, phase, lifecycle, state machine, upstream
#
# Consumer customization:
#   - Đặt thêm pattern vào env var ROADMAP_TRIGGER_REGEX (extended regex)
#   - Tắt hook: SKIP_ROADMAP_READING=1 hoặc SKIP_HOOKS=1
#
# Per CLAUDE.md: dùng `node -e` để parse JSON (jq không có trên Windows Git Bash).

set -uo pipefail

SPAN_HOOK_NAME="enforce-roadmap-reading"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_ROADMAP_READING:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_ROADMAP_READING"
  exit 0
fi

PROMPT=$(node -e '
try {
  const input = JSON.parse(require("fs").readFileSync(0, "utf-8"));
  process.stdout.write(input.prompt || "");
} catch (e) { process.exit(0); }
' <<< "$INPUT" 2>/dev/null)

[[ -z "$PROMPT" ]] && exit 0

LC_PROMPT=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# ─── Generic trigger detection ──────────────────────────────────────────────
TRIGGERED=0

# VN signals
if echo "$LC_PROMPT" | grep -qE 'tính năng|làm tính năng|implement|viết test|tạo test|scaffold|kịch bản'; then
  TRIGGERED=1
fi

# EN signals
if [[ $TRIGGERED -eq 0 ]]; then
  if echo "$LC_PROMPT" | grep -qE 'implement|build feature|write test|create test|test plan|spec file|new feature|add (a |the )?feature'; then
    TRIGGERED=1
  fi
fi

# Generic lifecycle/roadmap signals
if [[ $TRIGGERED -eq 0 ]]; then
  if echo "$LC_PROMPT" | grep -qE 'roadmap|phase|lifecycle|state machine|upstream|downstream'; then
    TRIGGERED=1
  fi
fi

# Path signals
if [[ $TRIGGERED -eq 0 ]]; then
  if echo "$LC_PROMPT" | grep -qE 'tests/api|tests/e2e|src/|\.local/test-hooks|test-hooks/'; then
    TRIGGERED=1
  fi
fi

# Consumer-defined extra trigger
if [[ $TRIGGERED -eq 0 && -n "${ROADMAP_TRIGGER_REGEX:-}" ]]; then
  if echo "$LC_PROMPT" | grep -qE "$ROADMAP_TRIGGER_REGEX"; then
    TRIGGERED=1
  fi
fi

[[ $TRIGGERED -eq 0 ]] && exit 0

# ─── Discover consumer's roadmap docs ───────────────────────────────────────
ROADMAP_README=""
ROADMAP_DOCS=()
if [[ -f "docs/roadmap/README.md" ]]; then
  ROADMAP_README="docs/roadmap/README.md"
fi
if [[ -d "docs/roadmap" ]]; then
  while IFS= read -r f; do
    ROADMAP_DOCS+=("$f")
  done < <(find docs/roadmap -maxdepth 3 -type f -name '*.md' 2>/dev/null | sort | head -20)
fi

# Nếu consumer chưa có roadmap → exit silent
if [[ -z "$ROADMAP_README" && ${#ROADMAP_DOCS[@]} -eq 0 ]]; then
  SPAN_DECISION="skip"
  SPAN_DETAIL="no-roadmap-docs"
  exit 0
fi

DOC_LIST=""
if [[ ${#ROADMAP_DOCS[@]} -gt 0 ]]; then
  DOC_LIST=$(printf '    • %s\n' "${ROADMAP_DOCS[@]}")
fi

# ─── Emit additionalContext JSON ────────────────────────────────────────────
OUT=$(node -e '
const readme = process.argv[1] || "";
const docList = process.argv[2] || "";
const lines = [
  "📚 ROADMAP READING REMINDER — phát hiện request liên quan implement/test feature.",
  "",
  "Trước khi sửa code / viết test, BẮT BUỘC đọc roadmap docs để hiểu:",
  "  • Upstream deps  — feature này cần state nào từ phase/feature khác?",
  "  • State         — sau khi vào feature này, hệ thống ở state gì?",
  "  • Constraints   — BE quirks, failure modes đã document?",
  "  • Service/Factory layer — gọi đúng API, KHÔNG bypass abstraction",
  "",
  "Workflow:",
  readme
    ? "  ① Read  " + readme + "  (index — xác nhận feature mapping)"
    : "  ① (no docs/roadmap/README.md found — consumer chưa setup index)",
  "  ② Read  doc của feature target — chú ý § \"Upstream\"",
  "  ③ ĐỆ QUY: với mỗi upstream identify ở bước ②, read doc upstream đó, lặp § \"Upstream\"",
  "          Dừng khi tới feature gốc (no upstream).",
  "",
  "Available roadmap docs trong consumer repo:",
  docList || "    (rỗng)",
  "",
  "Tại sao recursion: feature ở downstream chỉ hoạt động đúng nếu upstream được seed đúng state.",
  "",
  "Note: skills/test-quality-checklist/SKILL.md enforce riêng bởi orchestrate-test-automation hook.",
  "      Hook này chỉ focus vào dependency chain.",
  "",
  "Bypass: SKIP_ROADMAP_READING=1 (per-hook) hoặc SKIP_HOOKS=1 (master). Chỉ set khi đã đọc rồi.",
].join("\n");

const out = {
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: lines
  }
};
process.stdout.write(JSON.stringify(out));
' "$ROADMAP_README" "$DOC_LIST")
printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="docs_found=${#ROADMAP_DOCS[@]}"

exit 0
