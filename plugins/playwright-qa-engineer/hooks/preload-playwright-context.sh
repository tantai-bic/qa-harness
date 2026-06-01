#!/bin/bash
# UserPromptSubmit hook: pre-load Playwright QA skill docs vào context khi detect test-writing.
#
# Logic:
#   1. Detect prompt keyword test-writing (viết test, write test, spec.ts, etc.)
#   2. Check transcript: đã preload trong session này chưa? (search marker)
#   3. Nếu CHƯA → inject FULL content của 3 local skill docs (1 lần, cache_create):
#        - skills/playwright-setup/SKILL.md          (project structure + packages)
#        - skills/playwright-test-organization/SKILL.md  (Rule #6, service/factory, hierarchy)
#        - skills/playwright-qa-workflow/SKILL.md    (roadmap workflow, scope discipline)
#      + HEAD of bmad-workflows skills (nếu có):
#        - skills/test-quality-checklist/SKILL.md    (9 rules — head only)
#   4. Nếu ĐÃ → emit short reminder only (~50 tokens)
#
# Skill path resolution:
#   Local skills (priority):   ${CLAUDE_PLUGIN_ROOT}/skills/<name>/SKILL.md
#   bmad-workflows (fallback): ${CLAUDE_PLUGIN_ROOT}/../bmad-workflows/skills/<name>/SKILL.md
#   Consumer CWD (fallback):   skills/<name>/SKILL.md
#
# Cost ROI: 1× cache_create vs 5-10× Read calls = positive ROI in test-writing sessions.
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

# Trigger detection
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

PRELOAD_MARKER="🎓 QA CONTEXT PRELOADED"

ALREADY=0
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
  if grep -qF "$PRELOAD_MARKER" "$TRANSCRIPT_PATH" 2>/dev/null; then
    ALREADY=1
  fi
fi

if [[ $ALREADY -eq 1 ]]; then
  OUT=$(node -e '
const msg = [
  "♻️  QA context đã preloaded từ prompt trước. Skip re-injection.",
  "Local skills: @playwright-setup · @playwright-test-organization · @playwright-qa-workflow",
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
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
BMAD_ROOT="${PLUGIN_ROOT}/../bmad-workflows"

_read_local_skill() {
  local skill_name="$1"
  local max_lines="${2:-}"
  local local_path="${PLUGIN_ROOT}/skills/${skill_name}/SKILL.md"
  local cwd_path="skills/${skill_name}/SKILL.md"
  if [[ -n "$max_lines" ]]; then
    ( head -"$max_lines" "$local_path" 2>/dev/null \
      || head -"$max_lines" "$cwd_path" 2>/dev/null \
      || echo "(missing skill: ${skill_name})" )
  else
    ( cat "$local_path" 2>/dev/null \
      || cat "$cwd_path" 2>/dev/null \
      || echo "(missing skill: ${skill_name})" )
  fi
}

_read_bmad_skill() {
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

# First-time preload — read local playwright skills
SETUP_CONTENT=$(_read_local_skill "playwright-setup")
TESTORG_CONTENT=$(_read_local_skill "playwright-test-organization")
WORKFLOW_CONTENT=$(_read_local_skill "playwright-qa-workflow")
# Supplement with test-quality-checklist from bmad-workflows (head only)
CKL_CONTENT=$(_read_bmad_skill "skills/test-quality-checklist/SKILL.md" 80)

OUT=$(node -e '
const marker = process.argv[1];
const setup = process.argv[2];
const testorg = process.argv[3];
const workflow = process.argv[4];
const ckl = process.argv[5];
const msg = [
  marker + " — playwright QA skill docs đã load 1 lần cho session này.",
  "preload-playwright-context hook: đọc lần đầu tiên cho session → cache_create.",
  "Orchestrate hook KHÔNG cần Read lại các skill này (đã có trong context).",
  "",
  "══════════ skills/playwright-setup/SKILL.md ══════════",
  "",
  setup,
  "",
  "══════════ skills/playwright-test-organization/SKILL.md ══════════",
  "",
  testorg,
  "",
  "══════════ skills/playwright-qa-workflow/SKILL.md ══════════",
  "",
  workflow,
  "",
  "══════════ skills/test-quality-checklist/SKILL.md (head — 9 rules, từ bmad-workflows) ══════════",
  "",
  ckl,
  "",
  "══════════ END PRELOAD ══════════",
  "",
  "Bypass: SKIP_PLAYWRIGHT_PRELOAD=1 (per-hook) hoặc SKIP_HOOKS=1 (master).",
].join("\n");
process.stdout.write(JSON.stringify({
  hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: msg }
}));
' "$PRELOAD_MARKER" "$SETUP_CONTENT" "$TESTORG_CONTENT" "$WORKFLOW_CONTENT" "$CKL_CONTENT")
printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="mode=full_preload setup_bytes=${#SETUP_CONTENT} testorg_bytes=${#TESTORG_CONTENT} workflow_bytes=${#WORKFLOW_CONTENT}"

exit 0
