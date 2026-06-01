#!/bin/bash
# UserPromptSubmit hook: pre-load QA skill docs vào context khi detect test-writing.
#
# Logic:
#   1. Detect prompt keyword test-writing (viết test, write test, spec.ts, etc.)
#   2. Check transcript: đã preload trong session này chưa? (search marker)
#   3. Nếu CHƯA → inject FULL content của 3 docs (1 lần, cache_create ~6K tokens):
#        - skills/qa-engineer/SKILL.md          (code patterns)
#        - skills/qa-test-case/SKILL.md         (test design index)
#        - skills/test-quality-checklist/SKILL.md     (head — 9 rules)
#   4. Nếu ĐÃ → emit short reminder only (~50 tokens)
#
# Skill path resolution (priority order):
#   1. ${CLAUDE_PLUGIN_ROOT}/../bmad-workflows/skills/  (marketplace install)
#   2. skills/  (consumer CWD — nếu consumer có local copy)
#   Graceful fallback: "(missing ...)" nếu cả 2 không tìm thấy.
#
# Cost ROI: 1× $0.11 cache_create vs 5-10× Read calls × $0.10-0.20 = positive ROI in test-writing sessions.
#
# Bypass: SKIP_PLAYWRIGHT_PRELOAD=1 / SKIP_QA_PRELOAD=1 (legacy alias, per-hook)
#         SKIP_HOOKS=1 (master)

set -uo pipefail

SPAN_HOOK_NAME="preload-playwright-context"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

# SKIP_PLAYWRIGHT_PRELOAD (new) hoặc SKIP_QA_PRELOAD (legacy alias)
if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_PLAYWRIGHT_PRELOAD:-0}" == "1" || "${SKIP_QA_PRELOAD:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  if [[ "${SKIP_HOOKS:-0}" == "1" ]]; then
    SPAN_BYPASS="SKIP_HOOKS"
  elif [[ "${SKIP_PLAYWRIGHT_PRELOAD:-0}" == "1" ]]; then
    SPAN_BYPASS="SKIP_PLAYWRIGHT_PRELOAD"
  else
    SPAN_BYPASS="SKIP_QA_PRELOAD"
  fi
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

# Trigger detection (subset of test-writing triggers from orchestrate)
TRIGGERED=0
if echo "$LC_PROMPT" | grep -qE 'viết test|tạo test|generate test|làm test|write test|create test|spec\.ts|test automation|tests/api|tests/e2e|test-hooks/'; then
  TRIGGERED=1
fi
[[ $TRIGGERED -eq 0 ]] && exit 0

# Get transcript path to check if already preloaded
TRANSCRIPT_PATH=$(node -e '
try {
  const input = JSON.parse(require("fs").readFileSync(0, "utf-8"));
  process.stdout.write(input.transcript_path || "");
} catch (e) { process.exit(0); }
' <<< "$INPUT" 2>/dev/null)

# Marker phrase — uniquely identifies prior preload injection
PRELOAD_MARKER="🎓 QA CONTEXT PRELOADED"

ALREADY=0
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
  if grep -qF "$PRELOAD_MARKER" "$TRANSCRIPT_PATH" 2>/dev/null; then
    ALREADY=1
  fi
fi

if [[ $ALREADY -eq 1 ]]; then
  # Short reminder — no re-inject
  OUT=$(node -e '
const msg = [
  "♻️  QA context đã preloaded từ prompt trước. Skip re-injection.",
  "Refs available: @skills/qa-engineer/SKILL.md · @skills/qa-test-case/SKILL.md · @skills/test-quality-checklist/SKILL.md",
].join("\n");
process.stdout.write(JSON.stringify({
  hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: msg }
}));
')
  printf '%s' "$OUT"
  SPAN_DECISION="inject"
  SPAN_BYTES=${#OUT}
  SPAN_DETAIL="mode=reminder already_preloaded=1"
  exit 0
fi

# ─── Skill path resolution ──────────────────────────────────────────────────
# Primary: ${CLAUDE_PLUGIN_ROOT}/../bmad-workflows/skills/ (correct for marketplace)
# Fallback: skills/ (consumer CWD local copy)
BMAD_ROOT="${CLAUDE_PLUGIN_ROOT:-}/../bmad-workflows"

_read_skill() {
  local rel_path="$1"
  local max_lines="${2:-}"
  local bmad_path="${BMAD_ROOT}/${rel_path}"
  local cwd_path="${rel_path}"
  if [[ -n "$max_lines" ]]; then
    ( head -"$max_lines" "$bmad_path" 2>/dev/null \
      || head -"$max_lines" "$cwd_path" 2>/dev/null \
      || echo "(missing ${rel_path})" )
  else
    ( cat "$bmad_path" 2>/dev/null \
      || cat "$cwd_path" 2>/dev/null \
      || echo "(missing ${rel_path})" )
  fi
}

# First-time preload — read all 3 skill files
ENG_CONTENT=$(_read_skill "skills/qa-engineer/SKILL.md")
TC_CONTENT=$(_read_skill "skills/qa-test-case/SKILL.md")
# Only head ~80 lines of TEST-QUALITY-CHECKLIST (the 9-rule table is in first ~60 lines)
CKL_CONTENT=$(_read_skill "skills/test-quality-checklist/SKILL.md" 80)

# Emit additionalContext with full content
OUT=$(node -e '
const marker = process.argv[1];
const eng = process.argv[2];
const tc = process.argv[3];
const ckl = process.argv[4];
const msg = [
  marker + " — skill docs đã load 1 lần cho session này.",
  "Hook orchestrate-test-automation step ⓪ + step ②③④ KHÔNG cần Read lại (đã có trong context).",
  "Detail modules (boundary/equivalence/security/...) vẫn cần Read khi áp dụng cụ thể.",
  "",
  "════════════════════ skills/qa-engineer/SKILL.md (CODE PATTERNS) ════════════════════",
  "",
  eng,
  "",
  "════════════════════ skills/qa-test-case/SKILL.md (TEST DESIGN INDEX) ════════════════════",
  "",
  tc,
  "",
  "════════════════════ skills/test-quality-checklist/SKILL.md (head — 9 rules) ════════════════════",
  "",
  ckl,
  "",
  "════════════════════ END PRELOAD ════════════════════",
  "",
  "Bypass: SKIP_PLAYWRIGHT_PRELOAD=1 (per-hook) hoặc SKIP_HOOKS=1 (master).",
].join("\n");
process.stdout.write(JSON.stringify({
  hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: msg }
}));
' "$PRELOAD_MARKER" "$ENG_CONTENT" "$TC_CONTENT" "$CKL_CONTENT")
printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="mode=full_preload eng_bytes=${#ENG_CONTENT} tc_bytes=${#TC_CONTENT} ckl_bytes=${#CKL_CONTENT}"

exit 0
