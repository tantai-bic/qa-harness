#!/bin/bash
# PreToolUse Write|Edit hook: BLOCK viết test spec nếu fixture/helper/service/
# factory mà spec đó import CHƯA tồn tại. Buộc Claude tạo prerequisite trước.
#
# Detection logic:
#   1. Trigger chỉ khi target = tests/**/*.spec.ts
#   2. Parse content (tool_input.content cho Write, hoặc new_string cho Edit)
#      → trích các import `from "@src/.../*.{service,factory,fixture,helper}"`
#   3. Map @src/* alias → src/*. Check file exists trên disk.
#   4. Nếu ≥1 import THIẾU → exit 2 (block) với danh sách + hướng dẫn tạo.
#
# Lý do: hạn chế anti-pattern "viết test rồi mới tạo helper" → dễ inline
# hard-code data, skip parallel-safety check, drift khỏi Service/Factory
# discipline (rule #9 của test-quality-checklist).
#
# Bypass: SKIP_FIXTURE_PREREQ=1 (per-hook) hoặc SKIP_HOOKS=1 (master)

set -uo pipefail

SPAN_HOOK_NAME="enforce-fixture-helper-prerequisite"
SPAN_T0_NS="$(date +%s%N 2>/dev/null || echo 0)"

# ─── Bypass ────────────────────────────────────────────────────────────────
if [[ "${SKIP_HOOKS:-}" == "1" ]]; then
  SPAN_DECISION="bypass"; SPAN_BYPASS="SKIP_HOOKS"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi
if [[ "${SKIP_FIXTURE_PREREQ:-}" == "1" ]]; then
  SPAN_DECISION="bypass"; SPAN_BYPASS="SKIP_FIXTURE_PREREQ"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"

# ─── Extract tool_input.file_path + content (bash-only, tránh node startup) ─
FILE_PATH=$(printf '%s' "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
TOOL_NAME=$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')

# Skip nếu không phải test spec
if [[ -z "$FILE_PATH" ]] || [[ ! "$FILE_PATH" =~ tests/.*\.spec\.ts$ ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="not_test_spec"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── Lấy content tuỳ tool ──────────────────────────────────────────────────
# Write: tool_input.content   |   Edit: tool_input.new_string
# Dùng node 1-liner cho JSON parse an toàn (content có thể chứa quote, newline)
CONTENT=$(printf '%s' "$INPUT" | node -e '
let s = ""; process.stdin.on("data", d => s += d); process.stdin.on("end", () => {
  try {
    const j = JSON.parse(s);
    const ti = j.tool_input || {};
    process.stdout.write(ti.content || ti.new_string || "");
  } catch(e) { process.stdout.write(""); }
});' 2>/dev/null)

if [[ -z "$CONTENT" ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="empty_content"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── Parse imports: from "@src/.../X.{service,factory,fixture,helper}" ────
MISSING=()
MISSING_TYPE=()

while IFS= read -r line; do
  # Match: from "@src/<path>"  hoặc  import "@src/<path>"
  rel=$(echo "$line" | grep -oE '@src/[A-Za-z0-9_./\-]+' | head -1)
  [[ -z "$rel" ]] && continue

  # Chỉ check file có suffix prerequisite (service/factory/fixture/helper)
  if [[ ! "$rel" =~ \.(service|factory|fixture|helper)$ ]] && \
     [[ ! "$rel" =~ /(services|factories|fixtures|helpers)/ ]]; then
    continue
  fi

  # Resolve @src → ./src + thêm .ts
  rel_path="${rel/#@src/src}"
  [[ ! "$rel_path" =~ \.ts$ ]] && rel_path="${rel_path}.ts"

  if [[ ! -f "$rel_path" ]]; then
    # Detect type cho hint
    type="unknown"
    case "$rel_path" in
      *.service.ts|*/services/*) type="service" ;;
      *.factory.ts|*/factories/*) type="factory" ;;
      *.fixture.ts|*/fixtures/*) type="fixture" ;;
      *.helper.ts|*/helpers/*) type="helper" ;;
    esac
    MISSING+=("$rel_path")
    MISSING_TYPE+=("$type")
  fi
done < <(printf '%s\n' "$CONTENT" | grep -E '^\s*(import|from)' | head -50)

# ─── Decision ──────────────────────────────────────────────────────────────
if [[ ${#MISSING[@]} -eq 0 ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="all_prereq_exist"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── BLOCK ─────────────────────────────────────────────────────────────────
{
  echo "🚧 PREREQUISITE MISSING — KHÔNG cho viết test spec trước khi tạo helper/fixture/service/factory."
  echo ""
  echo "Target: $FILE_PATH"
  echo ""
  echo "Các file import nhưng CHƯA tồn tại:"
  for i in "${!MISSING[@]}"; do
    echo "  [${MISSING_TYPE[$i]}] ${MISSING[$i]}"
  done
  echo ""
  echo "═══ Action bắt buộc TRƯỚC khi retry Write ═══"
  echo "  1. Tạo các file MISSING ở trên (theo Module Creation Pattern"
  echo "     trong skills/qa-engineer/SKILL.md § Module Creation)"
  echo "  2. Service: <Module>Service.<action> + testName param truyền vào mọi call"
  echo "  3. Factory: create<Module>Payload() — parallel-safe, KHÔNG hard-code"
  echo "  4. Fixture (E2E): extend test fixture, scope = module"
  echo "  5. Helper: utility pure function, no side-effect"
  echo "  6. Verify import path khớp @src/* alias"
  echo "  7. Retry Write/Edit test spec"
  echo ""
  echo "Lý do: anti-pattern 'viết test rồi mới tạo helper' → dễ inline hard-code,"
  echo "skip parallel-safety, drift khỏi Service/Factory discipline (Rule #9)."
  echo ""
  echo "Bypass: SKIP_FIXTURE_PREREQ=1 (per-hook) hoặc SKIP_HOOKS=1 (master)."
} >&2

SPAN_DECISION="deny"
SPAN_BYTES=${#MISSING[@]}
SPAN_DETAIL="missing=${#MISSING[@]} tool=$TOOL_NAME"
source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true

exit 2
