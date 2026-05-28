#!/bin/bash
# PreToolUse Write|Edit hook: ép spec automation gắn đủ tags cho CICD
# selective execution.
#
# Required tag categories per test/describe block:
#   1. PRIORITY (1 of): @P0 @P1 @P2 @P3  ← phải match file name (P0-xxx.spec.ts)
#   2. LAYER    (1 of): @BE @FE          ← phải match path (tests/api → @BE, tests/e2e → @FE)
#   3. TYPE     (≥1 of): @Smoke @Sanity @Regression @Function @UI @UX
#
# Supported Playwright tag syntax (v1.42+):
#   test("login", { tag: ["@P0", "@BE", "@Smoke"] }, async () => {})
#   test.describe("Auth", { tag: "@BE" }, () => {})
#   test("login @P0 @BE @Smoke", async () => {})    ← legacy title-tag
#
# Bypass: SKIP_SPEC_TAGS=1 (per-hook) hoặc SKIP_HOOKS=1 (master)

set -uo pipefail

SPAN_HOOK_NAME="enforce-spec-tags"
SPAN_T0_NS="$(date +%s%N 2>/dev/null || echo 0)"

# ─── Bypass ────────────────────────────────────────────────────────────────
if [[ "${SKIP_HOOKS:-}" == "1" ]]; then
  SPAN_DECISION="bypass"; SPAN_BYPASS="SKIP_HOOKS"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi
if [[ "${SKIP_SPEC_TAGS:-}" == "1" ]]; then
  SPAN_DECISION="bypass"; SPAN_BYPASS="SKIP_SPEC_TAGS"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"

# ─── Extract file_path + tool ──────────────────────────────────────────────
FILE_PATH=$(printf '%s' "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
TOOL_NAME=$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')

# Normalize Windows backslash → forward slash + collapse multi-slash
# (bash ${//} substitution không reliable với backslash trên Git Bash)
# Note: JSON escape "\\" → bash captures 2 chars `\\` → tr → `//` → collapse `/`
FILE_PATH_NORM=$(printf '%s' "$FILE_PATH" | tr '\\' '/' 2>/dev/null | sed 's|/\+|/|g')

# Skip nếu không phải test spec
if [[ -z "$FILE_PATH_NORM" ]] || [[ ! "$FILE_PATH_NORM" =~ tests/.*\.spec\.ts$ ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="not_test_spec path=$FILE_PATH"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── Infer required tags from path + filename (dùng path normalized) ──────
EXPECTED_PRIORITY=""
case "$FILE_PATH_NORM" in
  */P0-*.spec.ts) EXPECTED_PRIORITY="@P0" ;;
  */P1-*.spec.ts) EXPECTED_PRIORITY="@P1" ;;
  */P2-*.spec.ts) EXPECTED_PRIORITY="@P2" ;;
  */P3-*.spec.ts) EXPECTED_PRIORITY="@P3" ;;
esac

EXPECTED_LAYER=""
case "$FILE_PATH_NORM" in
  */tests/api/*|tests/api/*)  EXPECTED_LAYER="@BE" ;;
  */tests/e2e/*|tests/e2e/*)  EXPECTED_LAYER="@FE" ;;
esac

# Skip nếu path không match convention (file ngoài tests/api hoặc tests/e2e)
if [[ -z "$EXPECTED_LAYER" ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="non_standard_path"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── Extract content (Write: content, Edit: new_string) ────────────────────
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

# ─── Validate tags ─────────────────────────────────────────────────────────
ISSUES=()

# 1. Priority tag — phải match file name
if [[ -n "$EXPECTED_PRIORITY" ]]; then
  if ! echo "$CONTENT" | grep -qF "$EXPECTED_PRIORITY"; then
    ISSUES+=("Thiếu priority tag $EXPECTED_PRIORITY (suy ra từ file name $(basename "$FILE_PATH"))")
  fi
  # Conflict: file P0-* nhưng có tag @P1/P2/P3
  for other in @P0 @P1 @P2 @P3; do
    if [[ "$other" != "$EXPECTED_PRIORITY" ]] && echo "$CONTENT" | grep -qF "$other"; then
      ISSUES+=("Conflict priority: file là $EXPECTED_PRIORITY nhưng spec dùng $other (sai Rule #6 — split priority)")
    fi
  done
else
  # File không có P0-/P1-/P2-/P3- prefix → cần có ≥1 priority tag
  if ! echo "$CONTENT" | grep -qE '@P[0-3]\b'; then
    ISSUES+=("Thiếu priority tag (≥1 của @P0/@P1/@P2/@P3). Khuyến nghị: rename file theo Rule #6 — P0-{feature}.spec.ts")
  fi
fi

# 2. Layer tag — phải match path
if ! echo "$CONTENT" | grep -qF "$EXPECTED_LAYER"; then
  ISSUES+=("Thiếu layer tag $EXPECTED_LAYER (suy ra từ path $(dirname "$FILE_PATH"))")
fi

# Conflict: tests/api/* nhưng có @FE (hoặc ngược lại)
OTHER_LAYER="@FE"
[[ "$EXPECTED_LAYER" == "@FE" ]] && OTHER_LAYER="@BE"
if echo "$CONTENT" | grep -qF "$OTHER_LAYER"; then
  ISSUES+=("Conflict layer: path là $EXPECTED_LAYER nhưng spec dùng $OTHER_LAYER (di chuyển file sang đúng folder)")
fi

# 3. Type tag — ≥1 của @Smoke @Sanity @Regression @Function @UI @UX
if ! echo "$CONTENT" | grep -qE '@(Smoke|Sanity|Regression|Function|UI|UX)\b'; then
  ISSUES+=("Thiếu type tag (≥1 của @Smoke @Sanity @Regression @Function @UI @UX)")
fi

# 4. Tag phải nằm trong block test/describe (KHÔNG chỉ comment hoặc đầu file)
# Heuristic: nếu có tag nhưng KHÔNG có chuỗi { tag: hoặc title chứa @ → có thể tag chỉ ở comment
if echo "$CONTENT" | grep -qE '@(P[0-3]|BE|FE|Smoke|Sanity|Regression|Function|UI|UX)\b'; then
  if ! echo "$CONTENT" | grep -qE '(tag:\s*\[|test\([^)]*@|test\.describe\([^)]*@)'; then
    ISSUES+=("Tag tồn tại nhưng KHÔNG gắn vào test()/describe(). Dùng syntax: test('name', { tag: ['@P0','@BE','@Smoke'] }, async () => {})")
  fi
fi

# ─── Decision ──────────────────────────────────────────────────────────────
if [[ ${#ISSUES[@]} -eq 0 ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="all_tags_valid"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── BLOCK ─────────────────────────────────────────────────────────────────
{
  echo "🏷️  SPEC TAGS MISSING/INVALID — KHÔNG cho Write/Edit spec thiếu tag CICD."
  echo ""
  echo "Target: $FILE_PATH_NORM"
  echo "Inferred: priority=${EXPECTED_PRIORITY:-<unknown>}  layer=$EXPECTED_LAYER"
  echo ""
  echo "Vi phạm:"
  for issue in "${ISSUES[@]}"; do
    echo "  • $issue"
  done
  echo ""
  echo "═══ Tag taxonomy bắt buộc ═══"
  echo "  • PRIORITY (1):  @P0 @P1 @P2 @P3       ← match file name"
  echo "  • LAYER    (1):  @BE @FE                 ← match path (tests/api → BE, tests/e2e → FE)"
  echo "  • TYPE   (≥1):   @Smoke @Sanity @Regression @Function @UI @UX"
  echo ""
  echo "═══ Syntax recommended (Playwright v1.42+) ═══"
  echo "  test.describe('Login', { tag: '$EXPECTED_LAYER' }, () => {"
  echo "    test('valid credentials', { tag: ['${EXPECTED_PRIORITY:-@P0}', '@Smoke', '@Function'] },"
  echo "      async ({ page }) => { /* ... */ }"
  echo "    );"
  echo "  });"
  echo ""
  echo "CICD usage: npx playwright test --grep '@P0' / --grep '@Smoke|@Sanity'"
  echo ""
  echo "Bypass: SKIP_SPEC_TAGS=1 (per-hook) hoặc SKIP_HOOKS=1 (master)."
} >&2

SPAN_DECISION="deny"
SPAN_BYTES=${#ISSUES[@]}
SPAN_DETAIL="issues=${#ISSUES[@]} prio=$EXPECTED_PRIORITY layer=$EXPECTED_LAYER tool=$TOOL_NAME"
source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true

exit 2
