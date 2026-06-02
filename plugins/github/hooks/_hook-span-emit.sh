#!/bin/bash
# Shared helper — source này từ enforcement hook để ghi pending span entry.
# Span thực tế được flush bởi session-stop.sh (batch 1 node call) để tránh
# Windows Git Bash detach latency (~300ms/hook × 7 hooks = ~2s overhead).
#
# Usage trong hook:
#   SPAN_HOOK_NAME="block-github-read"            # bắt buộc TRƯỚC khi source
#   INPUT=$(cat); SPAN_INPUT_JSON="$INPUT"
#   source "$(dirname "$0")/_hook-span-emit.sh"
#   # ... tại mỗi exit path, update SPAN_DECISION/SPAN_BYTES rồi exit
#
# Vars trap reads tại EXIT:
#   SPAN_HOOK_NAME   — required
#   SPAN_DECISION    — "inject" | "deny" | "skip" | "bypass" | "error" (default skip)
#   SPAN_BYTES       — byte count context injected / reason text (default 0)
#   SPAN_BYPASS      — bypass env var name (vd "SKIP_HOOKS"), trống nếu không
#   SPAN_DETAIL      — short note (no tabs/newlines — bash sanitizes)
#   SPAN_INPUT_JSON  — hook stdin JSON (cần cho session_id resolve)
#
# Output file: .claude/hooks/.hook-spans-pending/<safe_session>.tsv
#   Mỗi line: hook<TAB>decision<TAB>bytes<TAB>bypass<TAB>detail<TAB>t0_ns<TAB>tend_ns<TAB>exit_code

SPAN_T0_NS="${SPAN_T0_NS:-$(date +%s%N 2>/dev/null || echo 0)}"
SPAN_DECISION="${SPAN_DECISION:-skip}"
SPAN_BYTES="${SPAN_BYTES:-0}"
SPAN_BYPASS="${SPAN_BYPASS:-}"
SPAN_DETAIL="${SPAN_DETAIL:-}"
SPAN_INPUT_JSON="${SPAN_INPUT_JSON:-}"

__SPAN_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

__hook_span_emit_atexit() {
  local exit_code=$?
  [[ -z "${SPAN_HOOK_NAME:-}" ]] && return $exit_code

  # Bash-only session_id extraction (no node startup)
  local sid=""
  if [[ -n "${SPAN_INPUT_JSON:-}" ]]; then
    sid=$(printf '%s' "$SPAN_INPUT_JSON" | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
  fi
  [[ -z "$sid" ]] && return $exit_code

  # Sanitize safe_session — same rule as langfuse-helper.js safeSession()
  local safe_sid
  safe_sid=$(printf '%s' "$sid" | tr -c 'a-zA-Z0-9_-' '_' | cut -c1-64)
  [[ -z "$safe_sid" ]] && safe_sid="unknown"

  local pending_dir="${PWD}/.claude/hooks/.hook-spans-pending"
  mkdir -p "$pending_dir" 2>/dev/null || return $exit_code

  local t_end
  t_end=$(date +%s%N 2>/dev/null || echo 0)

  # Sanitize TSV fields — strip tabs + newlines (cheap; only DETAIL is risky)
  local clean_detail clean_bypass clean_hook clean_decision
  clean_detail=$(printf '%s' "$SPAN_DETAIL" | tr -d '\t\n\r' | cut -c1-200)
  clean_bypass=$(printf '%s' "$SPAN_BYPASS" | tr -d '\t\n\r' | cut -c1-50)
  clean_hook=$(printf '%s' "$SPAN_HOOK_NAME" | tr -d '\t\n\r' | cut -c1-80)
  clean_decision=$(printf '%s' "$SPAN_DECISION" | tr -d '\t\n\r' | cut -c1-20)

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$clean_hook" "$clean_decision" "$SPAN_BYTES" "$clean_bypass" \
    "$clean_detail" "$SPAN_T0_NS" "$t_end" "$exit_code" \
    >> "$pending_dir/$safe_sid.tsv" 2>/dev/null || true

  return $exit_code
}

trap __hook_span_emit_atexit EXIT
