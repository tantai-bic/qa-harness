#!/usr/bin/env bash
# PreToolUse Write|Edit hook: nhắc (KHÔNG block) khi spec test user-input
# nhưng KHÔNG có security test coverage (XSS / injection / 401 / 403).
#
# Mục đích: cover gap mà skill `qa-test-case/{backend,frontend}/*.md` document
# nhưng không có hook enforce. Hook nhẹ — chỉ EMIT warning ra stderr, KHÔNG
# block. Developer + Claude tự quyết: có cần thêm security test hay không.
#
# Trigger: Write|Edit trên tests/**/*.spec.ts CHỨA pattern user-input handling:
#   • API: body|payload|request.post|fillForm với data động từ factory
#   • E2E: page.fill, page.locator(...).fill, fillForm
#
# Skip nếu spec đã có ≥1 trong các signal:
#   • Tag @Security hoặc @XSS hoặc @Auth
#   • Mention 401/403/XSS/injection trong test title
#   • Import từ @src/utils/error-handler (typed error check)
#   • Có *WithoutAuth() call (401/403 test)
#
# Bypass: SKIP_SECURITY_REMINDER=1 (per-hook) hoặc SKIP_HOOKS=1 (master)

set -uo pipefail

SPAN_HOOK_NAME="enforce-security-test-presence"
SPAN_T0_NS="$(date +%s%N 2>/dev/null || echo 0)"

if [[ "${SKIP_HOOKS:-}" == "1" ]]; then
  SPAN_DECISION="bypass"; SPAN_BYPASS="SKIP_HOOKS"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi
if [[ "${SKIP_SECURITY_REMINDER:-}" == "1" ]]; then
  SPAN_DECISION="bypass"; SPAN_BYPASS="SKIP_SECURITY_REMINDER"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"

FILE_PATH=$(printf '%s' "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
FILE_PATH_NORM=$(printf '%s' "$FILE_PATH" | tr '\\' '/' 2>/dev/null | sed 's|/\+|/|g')

if [[ -z "$FILE_PATH_NORM" ]] || [[ ! "$FILE_PATH_NORM" =~ tests/.*\.spec\.ts$ ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="not_test_spec"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

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

# ─── Detect user-input handling ────────────────────────────────────────────
HANDLES_INPUT=0
case "$FILE_PATH_NORM" in
  */tests/api/*|tests/api/*)
    # API: body/payload/request.post với data từ factory
    if echo "$CONTENT" | grep -qE '\b(body|payload|data)\s*[:=]\s*create[A-Z]|request\.(post|put|patch).*\b(body|data)\b'; then
      HANDLES_INPUT=1
    fi
    ;;
  */tests/e2e/*|tests/e2e/*)
    # E2E: page.fill, .locator(...).fill, fillForm
    if echo "$CONTENT" | grep -qE 'page\.(fill|fillForm|type)|\.locator\([^)]+\)\.fill|fillForm\('; then
      HANDLES_INPUT=1
    fi
    ;;
esac

if [[ $HANDLES_INPUT -eq 0 ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="no_user_input_handling"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── Detect existing security coverage ────────────────────────────────────
HAS_SECURITY=0

# Signal 1: Security/XSS/Auth tag
if echo "$CONTENT" | grep -qE '@(Security|XSS|Auth|Injection)\b'; then
  HAS_SECURITY=1
fi

# Signal 2: Title mentions security concern
if [[ $HAS_SECURITY -eq 0 ]] && echo "$CONTENT" | grep -qiE 'test\([^)]*(401|403|unauthor|forbidden|xss|injection|sql\s+injection|sanitiz|escape|malicious)'; then
  HAS_SECURITY=1
fi

# Signal 3: Auth pattern (WithoutAuth / fresh context for 401-403)
if [[ $HAS_SECURITY -eq 0 ]] && echo "$CONTENT" | grep -qE '\b\w+WithoutAuth\(|browser\.newContext\(\s*\{\s*storageState\s*:\s*undefined'; then
  HAS_SECURITY=1
fi

# Signal 4: Imports security helper
if [[ $HAS_SECURITY -eq 0 ]] && echo "$CONTENT" | grep -qE 'from\s+["'\''"]@src/(utils|helpers)/(security|sanitize|escape|xss)'; then
  HAS_SECURITY=1
fi

if [[ $HAS_SECURITY -eq 1 ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="has_security_coverage"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── Warn (non-blocking) ──────────────────────────────────────────────────
# PreToolUse exit 0 với stderr → context injection, KHÔNG block.
# Để block bắt buộc: đổi exit 0 → exit 2.

LAYER="API"
SKILL_PATH="skills/qa-test-case/backend/security.md + injection-xss.md"
case "$FILE_PATH_NORM" in
  */tests/e2e/*|tests/e2e/*)
    LAYER="E2E"
    SKILL_PATH="skills/qa-test-case/frontend/xss-rendering.md"
    ;;
esac

{
  echo "⚠️  SECURITY TEST GAP — Spec xử lý user input nhưng chưa có security test coverage."
  echo ""
  echo "Target: $FILE_PATH_NORM (layer: $LAYER)"
  echo ""
  echo "Spec dùng pattern user-input ($([ "$LAYER" = API ] && echo 'body/payload/request.post với factory data' || echo 'page.fill / fillForm')) nhưng:"
  echo "  ✗ KHÔNG có tag @Security / @XSS / @Auth"
  echo "  ✗ KHÔNG có test cho 401/403/XSS/injection"
  echo "  ✗ KHÔNG dùng *WithoutAuth() hoặc security helper"
  echo ""
  echo "Khuyến nghị bổ sung (nếu requirement có yêu cầu security):"
  case "$LAYER" in
    API)
      echo "  • 401 — request không token → expect error.error.code match /^ERR_\\d+\$/"
      echo "  • 403 — request token role thấp → expect 403"
      echo "  • XSS payload — body chứa <script>alert(1)</script> → assert BE sanitize hoặc reject"
      echo "  • SQL injection — body chứa ' OR 1=1 -- → assert BE không leak data"
      echo "  • Pattern: dùng *WithoutAuth() / dedicated test user login → fresh context"
      ;;
    E2E)
      echo "  • XSS rendering — input <img src=x onerror=alert(1)> → assert DOM không execute script"
      echo "  • Form sanitize — paste HTML/script vào input → assert được escape khi render"
      echo "  • Auth redirect — không login truy cập protected page → redirect /login"
      echo "  • Pattern: page.fill(payload) → reload → expect render escaped (text content, not HTML)"
      ;;
  esac
  echo ""
  echo "Reference skill: $SKILL_PATH"
  echo "Tag: thêm @Security hoặc @XSS (xem skills/qa-test-case/common/spec-tags.md)"
  echo ""
  echo "Đây là NHẮC NHỞ, không block. Bypass: SKIP_SECURITY_REMINDER=1."
} >&2

SPAN_DECISION="warn"
SPAN_BYTES=1
SPAN_DETAIL="missing_security_$LAYER"
source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true

exit 0   # non-blocking warning
