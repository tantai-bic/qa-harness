#!/bin/bash
# SessionStart hook: check observability-specific consumer setup.
# Checks: LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY (warn only — không block)
# Bypass: SKIP_SETUP_CHECK=1 | SKIP_HOOKS=1 | SKIP_LANGFUSE=1

set -uo pipefail

SPAN_HOOK_NAME="observability-check-setup"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_SETUP_CHECK:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_SETUP_CHECK"
  exit 0
fi

# Load .env nếu có — cùng pattern với session-start.sh
if [[ -f ".env" ]]; then
  shopt -s extglob
  while IFS= read -r _ln || [[ -n "$_ln" ]]; do
    [[ -z "$_ln" || "$_ln" =~ ^[[:space:]]*# ]] && continue
    _k="${_ln%%=*}"; _k="${_k//[[:space:]]/}"
    _v="${_ln#*=}"; _v="${_v##*( )}"; _v="${_v%%*( )}"
    _v="${_v#\'}"; _v="${_v%\'}"; _v="${_v#\"}"; _v="${_v%\"}"
    [[ -n "$_k" && -n "$_v" ]] && export "$_k"="$_v"
  done < .env
fi

SOURCE=$(node -e '
try { process.stdout.write(JSON.parse(require("fs").readFileSync(0,"utf-8")).source||""); }
catch { process.exit(0); }
' <<< "$INPUT" 2>/dev/null)
[[ "$SOURCE" != "startup" ]] && { SPAN_DECISION="skip"; SPAN_DETAIL="source=$SOURCE"; exit 0; }

[[ -f ".claude-plugin/marketplace.json" ]] && { SPAN_DECISION="skip"; SPAN_DETAIL="plugin-self"; exit 0; }

# ─── Nếu SKIP_LANGFUSE=1 → Langfuse push tắt hoàn toàn, không cần warn ─────
if [[ "${SKIP_LANGFUSE:-0}" == "1" ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="SKIP_LANGFUSE=1"; exit 0
fi

# ─── Check Langfuse credentials ──────────────────────────────────────────────
HAS_PK="${LANGFUSE_PUBLIC_KEY:-}"
HAS_SK="${LANGFUSE_SECRET_KEY:-}"

if [[ -n "$HAS_PK" && -n "$HAS_SK" ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="lf-configured"; exit 0
fi

MISSING=()
[[ -z "$HAS_PK" ]] && MISSING+=("LANGFUSE_PUBLIC_KEY")
[[ -z "$HAS_SK" ]] && MISSING+=("LANGFUSE_SECRET_KEY")

HAS_ENV_FILE="no"
[[ -f ".env" ]] && HAS_ENV_FILE="yes"

OUT=$(node -e '
const missing = JSON.parse(process.argv[1]);
const hasEnvFile = process.argv[2] === "yes";
const out = {
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: [
      "📊 [observability] SETUP CHECK — Langfuse credentials chưa có:\n",
      missing.map((k,i) => "  " + (i+1) + ". `" + k + "` — chưa set trong env / .env").join("\n"),
      "",
      hasEnvFile
        ? "  File .env tồn tại nhưng thiếu key trên."
        : "  Chưa có file .env — tạo .env tại root project:",
      "",
      "  LANGFUSE_PUBLIC_KEY=pk-lf-xxxxxxxxxxxxxxxx",
      "  LANGFUSE_SECRET_KEY=sk-lf-xxxxxxxxxxxxxxxx",
      "  LANGFUSE_HOST=https://cloud.langfuse.com",
      "",
      "Ảnh hưởng: session traces, generation events, hook spans KHÔNG push được lên Langfuse.",
      "  Session logs vẫn lưu local tại .claude/session-logs/ (local archive luôn chạy).",
      "  Khi có credentials → flush thủ công: node .claude/hooks/langfuse-helper.js flush \"<sessionId>\"",
      "",
      "Tắt warning này: SKIP_LANGFUSE=1 (tắt toàn bộ Langfuse push) hoặc SKIP_SETUP_CHECK=1"
    ].join("\n")
  }
};
process.stdout.write(JSON.stringify(out));
' "$(printf '%s' "${MISSING[@]}" | node -e 'const l=require("fs").readFileSync(0,"utf-8").split(" ").filter(Boolean);process.stdout.write(JSON.stringify(l))')" "$HAS_ENV_FILE")

printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="missing-keys=${#MISSING[@]}"
exit 0
