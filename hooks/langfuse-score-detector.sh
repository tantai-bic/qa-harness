#!/bin/bash
# UserPromptSubmit hook: detect khi user yêu cầu ĐÁNH GIÁ một phiên trace
# → inject context hướng dẫn Claude tự fill 4 fields (traceId, name, value, comment)
# rồi push qua wrapper langfuse-push-score.sh.
#
# Trigger keywords (case-insensitive):
#   - VN: "đánh giá", "chấm điểm", "rating", "đánh giá phiên", "đánh giá trace",
#         "đánh giá session", "score session", "score trace"
#   - EN: "evaluate trace", "evaluate session", "score trace", "rate session",
#         "give score", "rate trace"
#
# Bypass: SKIP_HOOKS=1 hoặc SKIP_SCORE_DETECTOR=1

set -uo pipefail

SPAN_HOOK_NAME="langfuse-score-detector"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_SCORE_DETECTOR:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_SCORE_DETECTOR"
  exit 0
fi

# Detection + session_id extraction trong 1 node call — toLowerCase() handles
# Vietnamese Unicode (tr [:upper:] [:lower:] không cover).
# Output format: "<TRIGGERED 0|1>\t<session_id>"
DETECT=$(node -e '
try {
  const input = JSON.parse(require("fs").readFileSync(0, "utf-8"));
  const prompt = String(input.prompt || "").toLowerCase();
  const sid = input.session_id || "";
  const vn = /đánh giá[\s\S]{0,30}(phiên|trace|session|chat)|chấm điểm|đánh giá phiên|đánh giá trace/;
  const en = /evaluate[\s\S]{0,5}(trace|session|this chat|this)|score[\s\S]{0,8}(trace|session|this)|rate[\s\S]{0,8}(trace|session|chat)|give[\s\S]{0,10}score/;
  const triggered = vn.test(prompt) || en.test(prompt) ? 1 : 0;
  process.stdout.write(triggered + "\t" + sid);
} catch (e) { process.exit(0); }
' <<< "$INPUT" 2>/dev/null)

TRIGGERED="${DETECT%%$'\t'*}"
SESSION_ID="${DETECT#*$'\t'}"

[[ "$TRIGGERED" != "1" ]] && exit 0

# Lookup active prompt index từ session-map để derive traceId mặc định
TRACE_DEFAULT=""
if [[ -n "$SESSION_ID" ]]; then
  SAFE=$(echo "$SESSION_ID" | tr -c '[:alnum:]_-' '_' | cut -c1-64)
  MAP_FILE=".claude/hooks/.session-map/$SAFE"
  if [[ -f "$MAP_FILE" ]]; then
    LOG_PATH=$(cat "$MAP_FILE")
    IDX=$(basename "$LOG_PATH" | grep -oE '^prompt-[0-9]{3}' | grep -oE '[0-9]{3}')
    [[ -n "$IDX" ]] && TRACE_DEFAULT="${SAFE}-${IDX}"
  fi
fi

# Check langfuse configured
LF_OK="no"
if node .claude/hooks/langfuse-helper.js configured 2>/dev/null; then
  LF_OK="yes"
fi

# ─── Emit additionalContext ───
OUT=$(node -e '
const sessionId   = process.argv[1] || "(no session_id available)";
const traceDefault = process.argv[2] || "(không detect được — hỏi user nếu unclear)";
const lfOk        = process.argv[3];

const lfWarning = lfOk === "yes"
  ? "  ✅ Langfuse đã configured (LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY set)."
  : "  ⚠️  Langfuse CHƯA configured — score sẽ KHÔNG push được. Báo user set env trước.";

const msg = [
  "📊 LANGFUSE SCORE — phát hiện request đánh giá phiên trace.",
  "",
  "═══ Workflow tự fill 4 fields ═══",
  "Bạn (Claude) phải EXTRACT 4 thông tin sau từ conversation context, KHÔNG hỏi user lại trừ khi thật sự thiếu:",
  "",
  "  1. traceId        — ID của trace cần đánh giá.",
  "                       • Default cho prompt hiện hành:  " + traceDefault,
  "                       • Nếu user nói \"phiên này\" / \"chat này\" / \"current trace\" → dùng default.",
  "                       • Nếu user cho UUID khác → dùng cái user cho.",
  "                       • Format trong system: \"<safeSessionId>-NNN\" (NNN = prompt index, 001…)",
  "",
  "  2. name           — Tiêu chí chấm điểm (ngắn, snake-case hoặc kebab-case).",
  "                       Ví dụ chuẩn: user-satisfaction · hook-correctness · scope-discipline ·",
  "                                    test-quality · roadmap-coverage · service-pattern · rule-6-split",
  "                       Suy từ ngữ cảnh: user nói gì về cái họ đánh giá?",
  "",
  "  3. value          — Điểm số.",
  "                       • NUMERIC (0–1):  1.0 = perfect, 0.5 = OK, 0.0 = fail",
  "                       • BOOLEAN:        true / false",
  "                       • CATEGORICAL:    \"PASS\" / \"CONCERNS\" / \"FAIL\" / \"WAIVED\"",
  "                       Map từ tone user: \"tốt/chuẩn/perfect\" → 1.0, \"có vấn đề\" → 0.5, \"sai/fail\" → 0.0.",
  "",
  "  4. comment        — Câu giải thích NGẮN (1–2 câu), summarize lý do score đó.",
  "                       Cite evidence cụ thể: \"X tool calls\", \"Y reads doc Z\", \"file split đúng Rule #6\"...",
  "",
  "═══ Cách push score (1 lệnh Bash) ═══",
  "",
  "  bash .claude/hooks/langfuse-push-score.sh \\",
  "    --trace-id  \"<traceId>\" \\",
  "    --name      \"<name>\" \\",
  "    --value     <value> \\",
  "    --comment   \"<comment>\"",
  "",
  "Optional flags:",
  "    --session-id <id>           (default: trùng trace-id — để Langfuse group đúng session)",
  "    --data-type NUMERIC|BOOLEAN|CATEGORICAL  (default: auto-detect từ value)",
  "    --observation-id <id>       (nếu score 1 span/generation cụ thể trong trace)",
  "",
  "═══ Pre-flight ═══",
  lfWarning,
  "  Session ID context: " + sessionId,
  "",
  "═══ Workflow đề xuất ═══",
  "  1. Tóm tắt 1 câu: bạn hiểu user đang muốn score cái gì.",
  "  2. Đề xuất 4 fields cụ thể (đã fill sẵn) — show ngay cho user thấy.",
  "  3. Chạy Bash command push score.",
  "  4. Report kết quả: \"✓ pushed score X cho trace Y\" + Langfuse URL nếu biết.",
  "",
  "Nếu user muốn nhiều score (multi-dimensional eval) → chạy bash command nhiều lần, mỗi lần 1 name.",
  "",
  "Bypass: SKIP_SCORE_DETECTOR=1 hoặc SKIP_HOOKS=1.",
].join("\n");

process.stdout.write(JSON.stringify({
  hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext: msg }
}));
' "$SESSION_ID" "$TRACE_DEFAULT" "$LF_OK")
printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="trace_default=$TRACE_DEFAULT lf_configured=$LF_OK"

exit 0
