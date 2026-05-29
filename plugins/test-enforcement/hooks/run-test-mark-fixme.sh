#!/usr/bin/env bash
# PostToolUse Write|Edit hook: sau khi Write/Edit test spec, chạy Playwright
# spec đó. Nếu có test fail → tự đánh dấu `test.fixme()` cho từng test fail
# (preserve tags, options, args). Test pass giữ nguyên.
#
# Lý do: đảm bảo PR merge KHÔNG có spec đang fail mà chưa được flag — fail
# silently sẽ break CI khác hoặc hide regression.
#
# Yêu cầu consumer:
#   • Có playwright.config.ts ở cwd
#   • Có `npx playwright` chạy được (consumer đã `npm install`)
#
# Bypass: SKIP_RUN_TEST=1 (per-hook) hoặc SKIP_HOOKS=1 (master)
# Async: chạy background để không block tool result (max 90s timeout)

set -uo pipefail

SPAN_HOOK_NAME="run-test-mark-fixme"
SPAN_T0_NS="$(date +%s%N 2>/dev/null || echo 0)"

# ─── Bypass ────────────────────────────────────────────────────────────────
if [[ "${SKIP_HOOKS:-}" == "1" ]]; then
  SPAN_DECISION="bypass"; SPAN_BYPASS="SKIP_HOOKS"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi
if [[ "${SKIP_RUN_TEST:-}" == "1" ]]; then
  SPAN_DECISION="bypass"; SPAN_BYPASS="SKIP_RUN_TEST"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"

# ─── Extract + normalize file path ─────────────────────────────────────────
FILE_PATH=$(printf '%s' "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
FILE_PATH_NORM=$(printf '%s' "$FILE_PATH" | tr '\\' '/' 2>/dev/null | sed 's|/\+|/|g')

if [[ -z "$FILE_PATH_NORM" ]] || [[ ! "$FILE_PATH_NORM" =~ tests/.*\.spec\.ts$ ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="not_test_spec"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── Sanity check consumer setup ───────────────────────────────────────────
if [[ ! -f "$PWD/playwright.config.ts" ]] && [[ ! -f "$PWD/playwright.config.js" ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="no_playwright_config"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

if ! command -v npx >/dev/null 2>&1; then
  SPAN_DECISION="skip"; SPAN_DETAIL="no_npx"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── Resolve absolute spec path ────────────────────────────────────────────
SPEC_PATH="$FILE_PATH_NORM"
[[ ! "$SPEC_PATH" =~ ^/ ]] && [[ ! "$SPEC_PATH" =~ ^[A-Za-z]: ]] && SPEC_PATH="$PWD/$SPEC_PATH"

if [[ ! -f "$SPEC_PATH" ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="spec_not_exist"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── Run Playwright (JSON reporter) ────────────────────────────────────────
echo "[run-test-mark-fixme] Running: npx playwright test \"$SPEC_PATH\"" >&2

TIMEOUT_SEC="${RUN_TEST_TIMEOUT:-90}"
TMP_JSON=$(mktemp)
trap "rm -f $TMP_JSON" EXIT

# `timeout` command nếu có (gnu coreutils)
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_PREFIX="timeout ${TIMEOUT_SEC}s"
else
  TIMEOUT_PREFIX=""
fi

$TIMEOUT_PREFIX npx playwright test "$SPEC_PATH" \
  --reporter=json \
  --max-failures=999 \
  --workers=1 \
  > "$TMP_JSON" 2>/dev/null || true   # exit code non-zero khi có fail — bình thường

if [[ ! -s "$TMP_JSON" ]]; then
  echo "[run-test-mark-fixme] ⚠ Playwright không output (timeout / crash) — skip mark." >&2
  SPAN_DECISION="skip"; SPAN_DETAIL="playwright_no_output"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── Parse JSON → titles of failing tests ─────────────────────────────────
FAILING_TITLES=$(node -e '
const fs = require("fs");
let report;
try { report = JSON.parse(fs.readFileSync("'"$TMP_JSON"'", "utf-8")); }
catch (e) { process.exit(0); }

const failing = [];
function walk(suites) {
  for (const s of (suites || [])) {
    for (const spec of (s.specs || [])) {
      for (const t of (spec.tests || [])) {
        const status = t.status || (t.results && t.results[0] && t.results[0].status);
        if (status === "failed" || status === "timedOut" || status === "unexpected") {
          failing.push(spec.title);
        }
      }
    }
    if (s.suites) walk(s.suites);
  }
}
walk(report.suites);
process.stdout.write(failing.join("\n"));
' 2>/dev/null)

if [[ -z "$FAILING_TITLES" ]]; then
  echo "[run-test-mark-fixme] ✓ All tests pass — no mark needed." >&2
  SPAN_DECISION="skip"; SPAN_BYTES=0; SPAN_DETAIL="all_pass"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── Mark each failing test với .fixme() ───────────────────────────────────
COUNT=0
FAIL_LIST=""
while IFS= read -r title; do
  [[ -z "$title" ]] && continue
  # Escape title cho sed: chỉ escape các char đặc biệt mà title có thể chứa
  ESC_TITLE=$(printf '%s' "$title" | sed 's/[\/&]/\\&/g')

  # Match: test('<title>', ...   |   test("<title>", ...
  # Replace: test.fixme('<title>', ...
  # Tránh double-mark nếu đã có .fixme/.skip
  if grep -qE "test\.(fixme|skip)\s*\(\s*[\"']${ESC_TITLE//\\\&/.}[\"']" "$SPEC_PATH"; then
    continue   # đã marked rồi
  fi

  # Use sed to add .fixme after test( for matching title
  sed -i -E "s/\btest\s*\(\s*(['\"])${ESC_TITLE}\1/test.fixme(\1${ESC_TITLE}\1/g" "$SPEC_PATH"

  COUNT=$((COUNT + 1))
  FAIL_LIST+="  • ${title}"$'\n'
done <<< "$FAILING_TITLES"

if [[ $COUNT -eq 0 ]]; then
  echo "[run-test-mark-fixme] ⚠ Phát hiện $COUNT fail nhưng không sed được (titles không match) — manual check." >&2
  SPAN_DECISION="skip"; SPAN_DETAIL="sed_match_fail"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

{
  echo "🚨 RUN-TEST AUTO-MARK — Đã đánh dấu \`.fixme()\` cho $COUNT test fail trong:"
  echo "   $FILE_PATH_NORM"
  echo ""
  echo "Tests bị mark fixme:"
  printf '%s' "$FAIL_LIST"
  echo ""
  echo "Hành động bắt buộc tiếp theo:"
  echo "  1. Review từng test fail — debug root cause (BE bug? test logic sai? requirement đổi?)"
  echo "  2. Theo Hierarchy of Truth: test FAIL ≠ test sai. Check test-design trước khi sửa test."
  echo "  3. Nếu BE bug → log bug theo docs/templates/log-bug-api-template.md, giữ .fixme()"
  echo "  4. Nếu test logic sai → fix logic, xoá .fixme(), re-run"
  echo ""
  echo "CICD lưu ý: .fixme() vẫn xuất hiện trong report nhưng KHÔNG fail build."
  echo ""
  echo "Bypass: SKIP_RUN_TEST=1 (per-hook) hoặc SKIP_HOOKS=1 (master)."
} >&2

SPAN_DECISION="mutate"
SPAN_BYTES=$COUNT
SPAN_DETAIL="marked_fixme=$COUNT"
source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true

exit 0
