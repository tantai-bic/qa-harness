#!/bin/bash
# UserPromptSubmit hook: pre-load QA skill docs vào context khi detect test-writing.
#
# Logic:
#   1. Detect prompt keyword test-writing (viết test, write test, spec.ts, etc.)
#   2. Check transcript: đã preload trong session này chưa? (search marker)
#   3. Nếu CHƯA → inject FULL content của 3 docs (1 lần, cache_create ~6K tokens):
#        - docs/qa-engineer/skill.md          (code patterns)
#        - docs/qa-test-case/skill.md         (test design index)
#        - docs/TEST-QUALITY-CHECKLIST.md     (head — 9 rules)
#   4. Nếu ĐÃ → emit short reminder only (~50 tokens)
#
# Cost ROI: 1× $0.11 cache_create vs 5-10× Read calls × $0.10-0.20 = positive ROI in test-writing sessions.
#
# Bypass: SKIP_QA_PRELOAD=1 (per-hook) hoặc SKIP_HOOKS=1 (master)

set -uo pipefail

SPAN_HOOK_NAME="preload-qa-context"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_QA_PRELOAD:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_QA_PRELOAD"
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
  "Refs available: @docs/qa-engineer/skill.md · @docs/qa-test-case/skill.md · @docs/TEST-QUALITY-CHECKLIST.md",
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

# First-time preload — read all 3 files
ENG_CONTENT=$(cat docs/qa-engineer/skill.md 2>/dev/null || echo "(missing docs/qa-engineer/skill.md)")
TC_CONTENT=$(cat docs/qa-test-case/skill.md 2>/dev/null || echo "(missing docs/qa-test-case/skill.md)")
# Only head ~80 lines of TEST-QUALITY-CHECKLIST (the 9-rule table is in first ~60 lines)
CKL_CONTENT=$(head -80 docs/TEST-QUALITY-CHECKLIST.md 2>/dev/null || echo "(missing docs/TEST-QUALITY-CHECKLIST.md)")

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
  "════════════════════ docs/qa-engineer/skill.md (CODE PATTERNS) ════════════════════",
  "",
  eng,
  "",
  "════════════════════ docs/qa-test-case/skill.md (TEST DESIGN INDEX) ════════════════════",
  "",
  tc,
  "",
  "════════════════════ docs/TEST-QUALITY-CHECKLIST.md (head — 9 rules) ════════════════════",
  "",
  ckl,
  "",
  "════════════════════ END PRELOAD ════════════════════",
  "",
  "Bypass: SKIP_QA_PRELOAD=1 (per-hook) hoặc SKIP_HOOKS=1 (master).",
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
