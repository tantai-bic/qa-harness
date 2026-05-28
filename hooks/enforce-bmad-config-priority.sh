#!/bin/bash
# UserPromptSubmit hook: ép Claude đọc file _bmad/* theo PRIORITY
#   1. ./_bmad/<path>                              ← CONSUMER override (wins)
#   2. ${CLAUDE_PLUGIN_ROOT}/_bmad/<path>          ← PLUGIN default fallback
#
# Mục đích: cho phép consumer customize riêng BMAD (agent, workflow, task) cho
# 1 project mà KHÔNG cần fork plugin. Consumer chỉ tạo file ở ./_bmad/<path>
# cùng relative path với plugin → tự động win.
#
# Scope: config.yaml, agents/*.md, workflows/**/*.{yaml,md}, tasks/*.md, ...
#
# Bypass: SKIP_BMAD_PRIORITY=1 (per-hook) hoặc SKIP_HOOKS=1 (master)

set -uo pipefail

SPAN_HOOK_NAME="enforce-bmad-config-priority"
SPAN_T0_NS="$(date +%s%N 2>/dev/null || echo 0)"

# ─── Bypass ────────────────────────────────────────────────────────────────
if [[ "${SKIP_HOOKS:-}" == "1" ]]; then
  SPAN_DECISION="bypass"; SPAN_BYPASS="SKIP_HOOKS"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi
if [[ "${SKIP_BMAD_PRIORITY:-}" == "1" ]]; then
  SPAN_DECISION="bypass"; SPAN_BYPASS="SKIP_BMAD_PRIORITY"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"

# ─── Path resolution ───────────────────────────────────────────────────────
CONSUMER_BMAD="$PWD/_bmad"
PLUGIN_BMAD="${CLAUDE_PLUGIN_ROOT:-}/_bmad"

# Skip nếu plugin _bmad không tồn tại (hook chạy ngoài plugin context)
if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" || ! -d "$PLUGIN_BMAD" ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="plugin _bmad not found"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── Detect consumer overrides ────────────────────────────────────────────
OVERRIDES=""
OVERRIDE_COUNT=0
if [[ -d "$CONSUMER_BMAD" ]]; then
  while IFS= read -r f; do
    rel="${f#$CONSUMER_BMAD/}"
    if [[ -f "$PLUGIN_BMAD/$rel" ]]; then
      OVERRIDES+="  - _bmad/$rel"$'\n'
      OVERRIDE_COUNT=$((OVERRIDE_COUNT + 1))
    fi
  done < <(find "$CONSUMER_BMAD" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.md" -o -name "*.xml" \) 2>/dev/null)
fi

# ─── Inject context ────────────────────────────────────────────────────────
{
  echo "📚 BMAD FILE PRIORITY — đọc _bmad/* theo thứ tự:"
  echo ""
  echo "  1. ./_bmad/<path>                          ← CONSUMER override (wins)"
  echo "  2. \${CLAUDE_PLUGIN_ROOT}/_bmad/<path>      ← PLUGIN default fallback"
  echo ""
  echo "Áp dụng cho mọi file dưới _bmad/: config.yaml, agents/*.md,"
  echo "workflows/**/*.{yaml,md}, tasks/*.md, core/**, ..."
  echo ""
  echo "Quy tắc bắt buộc:"
  echo "  • TRƯỚC khi đọc bất kỳ file _bmad/<path>, KIỂM TRA ./_bmad/<path> trước"
  echo "  • Chỉ fallback \${CLAUDE_PLUGIN_ROOT}/_bmad/<path> nếu consumer KHÔNG có"
  echo "  • KHÔNG merge consumer + plugin: file consumer override LÀ FULL replacement"
  echo "  • Áp dụng cho cả relative path \`{project-root}/_bmad/...\` trong agent YAML"
  echo ""

  if [[ $OVERRIDE_COUNT -gt 0 ]]; then
    echo "🔧 Consumer overrides detected ($OVERRIDE_COUNT file) — ƯU TIÊN ĐỌC consumer version:"
    echo "$OVERRIDES" | head -20
    if [[ $OVERRIDE_COUNT -gt 20 ]]; then
      echo "  ... (+$((OVERRIDE_COUNT - 20)) more — xem full ở ./_bmad/)"
    fi
  elif [[ -d "$CONSUMER_BMAD" ]]; then
    echo "ℹ Consumer có ./_bmad/ nhưng KHÔNG file nào override plugin. Dùng plugin default toàn bộ."
  else
    echo "ℹ Consumer KHÔNG có ./_bmad/ → toàn bộ dùng plugin default. Tạo ./_bmad/<path> để override."
  fi

  echo ""
  echo "Bypass: SKIP_BMAD_PRIORITY=1 (per-hook) hoặc SKIP_HOOKS=1 (master)."
}

# ─── Telemetry ─────────────────────────────────────────────────────────────
SPAN_DECISION="inject"
SPAN_BYTES=$OVERRIDE_COUNT
SPAN_DETAIL="overrides=$OVERRIDE_COUNT consumer_bmad=$([[ -d $CONSUMER_BMAD ]] && echo yes || echo no)"
source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true

exit 0
