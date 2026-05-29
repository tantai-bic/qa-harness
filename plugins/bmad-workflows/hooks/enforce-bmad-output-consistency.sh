#!/bin/bash
# UserPromptSubmit hook: ép bmad agent activation output format consistent.
#
# Vấn đề observed (Langfuse A/B):
#   • Trace 8ac403da (bmad dev, harness-off): 2,172 output tokens
#   • Trace 89fee3f7 (bmad dev, harness):       974 output tokens
#   → Variance 2.2× với cùng prompt /bmad:bmm:agents:dev. Lý do: LLM "tự thêm"
#     flourish ("👋", "Sẵn sàng thực thi", session vars dump, role description...).
#
# Solution: hook inject STRICT template + hard constraints khi detect bmad slash command.
#   Output budget: ≤250 tokens (~150 words tiếng Việt)
#
# Trigger: prompt match /bmad:bmm:agents:<name> hoặc /bmad:<plugin>:agents:<name>
# Bypass: SKIP_BMAD_OUTPUT=1 (per-hook) hoặc SKIP_HOOKS=1 (master)

set -uo pipefail

SPAN_HOOK_NAME="enforce-bmad-output-consistency"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_BMAD_OUTPUT:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_BMAD_OUTPUT"
  exit 0
fi

# Extract agent name từ slash command pattern
AGENT_NAME=$(node -e '
try {
  const input = JSON.parse(require("fs").readFileSync(0, "utf-8"));
  const prompt = String(input.prompt || "");
  // Match /bmad:bmm:agents:<name> hoặc /bmad:<anything>:agents:<name>
  const m = prompt.match(/\/bmad(?::[a-z0-9-]+)+:agents:([a-z][a-z0-9-]*)/i);
  if (m) process.stdout.write(m[1].toLowerCase());
} catch (e) { process.exit(0); }
' <<< "$INPUT" 2>/dev/null)

# Không phải bmad activation → exit silent
[[ -z "$AGENT_NAME" ]] && exit 0

OUT=$(node -e '
const agent = process.argv[1];
const msg = [
  "🤖 BMAD AGENT OUTPUT CONSISTENCY GATE — agent activation detected: \"" + agent + "\"",
  "",
  "Lý do gate: token output variance đã đo (cùng prompt /bmad:bmm:agents:" + agent + "):",
  "  • 2,172 tokens (verbose case)  vs  974 tokens (lean case)  →  2.2× variance",
  "  • Cùng activation script, cùng agent YAML, NHƯNG LLM tự thêm flourish + dump session vars.",
  "",
  "═══ TEMPLATE BẮT BUỘC (exact format) ═══",
  "",
  "  {icon} Xin chào **{user_name}**! Tôi là **{agent_name}** — {role_one_line}.",
  "",
  "  **Menu:**",
  "",
  "  {menu_items — exact format từ <menu> trong agent YAML, KHÔNG translate}",
  "",
  "  Nhập số hoặc command (vd: `*X`).",
  "",
  "═══ HARD CONSTRAINTS (KHÔNG vi phạm) ═══",
  "",
  "  ❌ KHÔNG dump session variables (\"Config loaded. Variables stored: ...\")",
  "  ❌ KHÔNG thêm flourish: \"👋\", \"💻\", \"💡\", \"🎯\" (chỉ icon từ agent YAML)",
  "  ❌ KHÔNG add tagline: \"Sẵn sàng thực thi\", \"Sẵn sàng giúp\", \"với độ chính xác cao nhất\"",
  "  ❌ KHÔNG mô tả persona/principles dài (đã trong YAML, user không cần lặp)",
  "  ❌ KHÔNG translate menu items sang Vietnamese — giữ exact wording từ <menu>",
  "  ❌ KHÔNG add \"---\" separator hoặc heading section nhiều layer",
  "  ❌ KHÔNG show role expanded (vd \"Developer Agent của bạn, chuyên trách...\")",
  "",
  "  ✓ Output budget: ≤250 tokens (~150 từ tiếng Việt)",
  "  ✓ STOP sau menu — WAIT user input (KHÔNG auto-execute menu item)",
  "  ✓ TTS bmad-speak.sh fire SAU text output (không trước, không thay thế)",
  "  ✓ Greeting line 1: \"{icon} Xin chào **{user_name}**! Tôi là **{agent}** — {role}.\"",
  "  ✓ Menu line per item: \"N. **[X]** `*cmd` — Description\"",
  "",
  "═══ CHECKLIST trước khi output ═══",
  "  ☐ Đã load config.yaml, KHÔNG cần verbose acknowledge",
  "  ☐ Đếm token output dự kiến ≤250",
  "  ☐ Menu items khớp 100% với agent YAML <menu>",
  "  ☐ Không có emoji nào ngoài agent icon",
  "  ☐ Đã có \"Nhập số hoặc command\" prompt cuối",
  "",
  "Vì sao quan trọng: consistency = predictable UX + cost control + automatable testing.",
  "Variance 2× tokens = $0.04/activation × 1000 activations/tháng = $40 lãng phí + UX inconsistent.",
  "",
  "Bypass: SKIP_BMAD_OUTPUT=1 (per-hook) hoặc SKIP_HOOKS=1 (master).",
].join("\n");

const out = {
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: msg
  }
};
process.stdout.write(JSON.stringify(out));
' "$AGENT_NAME")
printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="agent=$AGENT_NAME"

exit 0
