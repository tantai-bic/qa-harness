#!/bin/bash
# UserPromptSubmit hook: extend BMAD dev agent menu với mục Playwright setup.
#
# Trigger khi user activate BMAD dev agent (`/bmad-workflows:bmad:bmm:agents:dev`
# hoặc các slash command variant). Inject additionalContext khuyến nghị dev agent
# thêm menu item [PS] và load skill `playwright-setup` khi user chọn.
#
# Logic:
#   1. Detect prompt activate dev agent (chứa `bmm:agents:dev`)
#   2. Scan transcript: đã inject menu extension trong session chưa? (marker check)
#   3. Nếu CHƯA → inject menu item description + skill path
#   4. Nếu ĐÃ → skip silent (tránh inject lặp mỗi prompt)
#
# Trigger keywords (case-insensitive):
#   - bmm:agents:dev                    (slash command path)
#   - bmad-workflows:bmad:bmm:agents:dev (full plugin slash command)
#
# Bypass: SKIP_DEV_PLAYWRIGHT_MENU=1 (per-hook) hoặc SKIP_HOOKS=1 (master)
#
# Per CLAUDE.md: node -e (jq không có trên Windows Git Bash).

set -uo pipefail

SPAN_HOOK_NAME="inject-dev-playwright-menu"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_DEV_PLAYWRIGHT_MENU:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_DEV_PLAYWRIGHT_MENU"
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

# Trigger detection: BMAD dev agent activation
# `bmm:agents:dev` là unique đủ — chỉ match dev agent slash command path
TRIGGERED=0
if echo "$LC_PROMPT" | grep -qE 'bmm:agents:dev'; then
  TRIGGERED=1
fi
[[ $TRIGGERED -eq 0 ]] && exit 0

# Check transcript: đã inject menu extension trong session chưa?
TRANSCRIPT_PATH=$(node -e '
try {
  const input = JSON.parse(require("fs").readFileSync(0, "utf-8"));
  process.stdout.write(input.transcript_path || "");
} catch (e) { process.exit(0); }
' <<< "$INPUT" 2>/dev/null)

INJECT_MARKER="🎭 PLAYWRIGHT SETUP MENU EXTENSION"

ALREADY=0
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
  if grep -qF "$INJECT_MARKER" "$TRANSCRIPT_PATH" 2>/dev/null; then
    ALREADY=1
  fi
fi

if [[ $ALREADY -eq 1 ]]; then
  SPAN_DECISION="skip"
  SPAN_DETAIL="already-injected"
  exit 0
fi

# Resolve absolute skill path
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
SKILL_PATH="${PLUGIN_ROOT}/skills/playwright-setup/SKILL.md"

OUT=$(node -e '
const skillPath = process.argv[1];
const msg = [
  "🎭 PLAYWRIGHT SETUP MENU EXTENSION (từ playwright-qa-engineer plugin)",
  "",
  "Khi hiển thị menu của dev agent (Amelia 💻), THÊM 1 menu item NỮA vào danh sách",
  "(đặt giữa [CR] code-review và [PM] party-mode):",
  "",
  "  [PS] *playwright-setup (hoặc fuzzy match \"setup playwright\" / \"playwright setup\")",
  "       → Setup Playwright project từ zero (load skill playwright-setup)",
  "",
  "Khi user chọn PS (số thứ tự hoặc tên):",
  "  1. Read skill: " + skillPath,
  "  2. Follow hướng dẫn trong skill — đặc biệt:",
  "       • Section 2: cài @playwright/test + husky + lint-staged + eslint + prettier",
  "       • Section 4: husky init + sửa .husky/pre-commit chạy lint-staged",
  "       • Section 5: bootstrap commands (5 bước từ npm init → verify)",
  "  3. Verify từng bước với consumer (xác nhận file/folder tồn tại) trước khi proceed",
  "  4. Khi xong: thông báo \"Playwright setup hoàn tất\" + restart Claude session để",
  "       check-playwright-setup.sh re-validate",
  "  5. STAY IN CHARACTER (Amelia, dev agent) — quay lại menu sau khi hoàn thành",
  "",
  "Mục đích: consumer dùng playwright-qa-engineer plugin được Amelia hướng dẫn setup",
  "         chuẩn (Playwright + husky + lint-staged toolchain), tránh boilerplate sai.",
  "",
  "Bypass: SKIP_DEV_PLAYWRIGHT_MENU=1 (per-hook) hoặc SKIP_HOOKS=1 (master).",
].join("\n");

process.stdout.write(JSON.stringify({
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: msg
  }
}));
' "$SKILL_PATH")

printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="dev-agent-activation menu-item=PS"

exit 0
