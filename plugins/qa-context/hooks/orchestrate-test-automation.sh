#!/bin/bash
# UserPromptSubmit hook: orchestrate test automation workflow.
#
# Trigger khi user prompt liên quan viết / tạo / generate test automation.
# Emit reminder về:
#   - Scope discipline: KHÔNG drift sang module khác (chỉ làm đúng module user hỏi)
#   - Per-module workflow: Service + Factory đúng module (KHÔNG generic)
#   - Rule #6 (skills/test-quality-checklist/SKILL.md): SPLIT P0 / P1 / P2 vào file RIÊNG
#   - Hierarchy of Truth: test-design → test code → BE → API-DOC
#   - Required reads: skills/test-quality-checklist/SKILL.md + skills/qa-test-case/**
#
# Trigger keywords (case-insensitive):
#   - VN: viết test, tạo test, generate test, làm test, automation, kịch bản test,
#         test case, đặt test, scaffold test
#   - EN: write test, create test, generate test, automate, test automation,
#         test suite, spec file, *.spec.ts, P0/P1/P2/P3
#   - Path: tests/api, tests/e2e, .local/test-hooks
#
# Bypass: SKIP_TEST_ORCHESTRATION=1  (per-hook)
#         SKIP_HOOKS=1               (master — disables all bypass-aware hooks)
#
# Per CLAUDE.md: dùng `node -e` để parse JSON (jq không có trên Windows Git Bash).

set -uo pipefail

SPAN_HOOK_NAME="orchestrate-test-automation"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_TEST_ORCHESTRATION:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_TEST_ORCHESTRATION"
  exit 0
fi

PROMPT=$(node -e '
try {
  const input = JSON.parse(require("fs").readFileSync(0, "utf-8"));
  process.stdout.write(input.prompt || "");
} catch (e) { process.exit(0); }
' <<< "$INPUT" 2>/dev/null)

[[ -z "$PROMPT" ]] && exit 0

# Scan transcript: skills/test-quality-checklist/SKILL.md đã đọc trong session chưa?
# Đọc 1 lần là đủ cho cả session → hook chỉ remind khi MISSING.
TRANSCRIPT_PATH=$(node -e '
try {
  const input = JSON.parse(require("fs").readFileSync(0, "utf-8"));
  process.stdout.write(input.transcript_path || "");
} catch (e) { process.exit(0); }
' <<< "$INPUT" 2>/dev/null)

CHECKLIST_READ=0
QA_PRELOADED=0
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
  if grep -qE 'skills/test-quality-checklist/SKILL\.md|TEST-QUALITY-CHECKLIST\.md' "$TRANSCRIPT_PATH" 2>/dev/null; then
    CHECKLIST_READ=1
  fi
  # Detect preload-qa-context hook đã inject content trong session chưa
  # → Nếu rồi: skip toàn bộ Section B (qa-engineer + qa-test-case docs đã có trong context)
  if grep -qF '🎓 QA CONTEXT PRELOADED' "$TRANSCRIPT_PATH" 2>/dev/null; then
    QA_PRELOADED=1
  fi
fi

LC_PROMPT=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# ─── Trigger detection ──────────────────────────────────────────────────────
TRIGGERED=0

# Vietnamese verbs + nouns
if echo "$LC_PROMPT" | grep -qE 'viết test|tạo test|generate test|làm test|scaffold test|automation|kịch bản test|đặt test|test case|test automation'; then
  TRIGGERED=1
fi

# English verbs + nouns
if [[ $TRIGGERED -eq 0 ]]; then
  if echo "$LC_PROMPT" | grep -qE 'write test|create test|generate test|automate|test suite|spec file|\.spec\.ts|p0[ -]*test|p1[ -]*test|p2[ -]*test|p3[ -]*test'; then
    TRIGGERED=1
  fi
fi

# Test path signals
if [[ $TRIGGERED -eq 0 ]]; then
  if echo "$LC_PROMPT" | grep -qE 'tests/api|tests/e2e|\.local/test-hooks|test-hooks/'; then
    TRIGGERED=1
  fi
fi

[[ $TRIGGERED -eq 0 ]] && exit 0   # SPAN_DECISION default "skip"

# ─── Downgrade: TEXT-ONLY edit detection ────────────────────────────────────
# Phân biệt CODE_LOGIC (write/add/implement test) vs TEXT_ONLY (rename, fix typo,
# update message/string/label). TEXT_ONLY → skip full skills load, chỉ inject
# nhắc giữ tags + structure.
#
# LOGIC keyword (full orchestration):
#   viết/tạo/thêm test, write/create/generate/add test, implement, scaffold,
#   assertion, kịch bản, test case, new test, refactor logic
#
# TEXT_ONLY keyword (downgrade, KHÔNG load skills):
#   đổi/sửa tên, đổi text/string/label/tiêu đề/message, rename, fix typo,
#   update text/string/label/title/message/wording, change wording, reword
TEXT_ONLY=0
LOGIC_KW=0

# LOGIC signals
if echo "$LC_PROMPT" | grep -qE '(viết|tạo|thêm|add|create|generate|write|implement|scaffold|làm|automate).*(test|spec|case|assertion|kịch bản)|new test|test mới|spec mới|refactor (test|logic|assertion)'; then
  LOGIC_KW=1
fi

# TEXT-ONLY signals (chỉ count nếu KHÔNG có logic keyword)
if [[ $LOGIC_KW -eq 0 ]]; then
  if echo "$LC_PROMPT" | grep -qE '(đổi|sửa|update|fix|rename|change|reword)\s*([a-zà-ỹ ]+\s)?(tên|text|string|label|tiêu đề|message|describe|title|typo|wording|tên test|tên describe|tên describe)'; then
    TEXT_ONLY=1
  fi
fi

if [[ $TEXT_ONLY -eq 1 ]]; then
  cat <<EOF
✏️ TEXT-ONLY EDIT detected — SKIP full QA skills orchestration (chỉ sửa text/string/label, không thay đổi logic).

Lưu ý BẮT BUỘC khi edit text trên test spec:
  • GIỮ NGUYÊN tags (@P0/@P1/@P2/@P3, @BE/@FE, @Smoke/@Sanity/@Regression/@Function/@UI/@UX) — KHÔNG xoá khi rename describe/test
  • GIỮ NGUYÊN import structure (\`@src/*.{service,factory,fixture,helper}\`)
  • GIỮ NGUYÊN assertion logic — chỉ string/label được phép thay đổi
  • Không cần load qa-test-case skills (boundary, equivalence, decision-table) vì không sinh test mới
  • enforce-spec-tags hook vẫn fire → nếu tag bị xoá nhầm sẽ block

Nếu thực sự cần thay đổi LOGIC test → re-prompt với từ khoá rõ:
  "viết test mới", "thêm assertion", "add test case", "refactor assertion logic", ...

Bypass: SKIP_TEST_ORCHESTRATION=1 (per-hook) hoặc SKIP_HOOKS=1 (master).
EOF
  SPAN_DECISION="inject"
  SPAN_BYTES=1
  SPAN_DETAIL="text_only_downgrade"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# ─── Module hint extraction (generic) ───────────────────────────────────────
# Tìm hint từ pattern phổ biến: "module X", "feature X", "viết test X",
# "X.spec.ts", "tests/.../X/...". Consumer có thể inject keyword list cụ thể
# qua env MODULE_KEYWORDS (space-separated list).
MODULE_HINT=""
if [[ -n "${MODULE_KEYWORDS:-}" ]]; then
  for KW in $MODULE_KEYWORDS; do
    KW_LC=$(echo "$KW" | tr '[:upper:]' '[:lower:]')
    if echo "$LC_PROMPT" | grep -qE "\b${KW_LC}\b"; then
      MODULE_HINT="$KW_LC"
      break
    fi
  done
fi
# Fallback patterns — try most specific first (verb + preposition + noun),
# then verb + noun, then "module|feature" + noun.
for PAT in \
    '(viết test|tạo test|write test|create test)[[:space:]]+(cho|for|của)[[:space:]]+(module|feature)?[[:space:]]*[a-z][a-z0-9_-]+' \
    '(viết test|tạo test|write test|create test)[[:space:]]+(module|feature)[[:space:]]+[a-z][a-z0-9_-]+' \
    '(module|feature)[[:space:]]+[a-z][a-z0-9_-]+'; do
  CAND=$(echo "$LC_PROMPT" | grep -oE "$PAT" | head -1 | awk '{print $NF}')
  if [[ -n "$CAND" && "$CAND" != "module" && "$CAND" != "feature" ]]; then
    MODULE_HINT="$CAND"
    break
  fi
done
if [[ -z "$MODULE_HINT" ]]; then
  MODULE_HINT=$(echo "$LC_PROMPT" | grep -oE '[a-z][a-z0-9_-]+\.spec\.[tj]sx?' | head -1 | sed 's/\.spec\.[tj]sx\?$//; s/^p[0-9]-//')
fi
if [[ -z "$MODULE_HINT" ]]; then
  MODULE_HINT=$(echo "$LC_PROMPT" | grep -oE 'tests/(api|e2e)/[a-z][a-z0-9_-]+' | head -1 | awk -F/ '{print $NF}')
fi

# ─── Emit additionalContext JSON ────────────────────────────────────────────
OUT=$(node -e '
const moduleHint     = process.argv[1] || "";
const checklistRead  = process.argv[2] === "1";
const qaPreloaded    = process.argv[3] === "1";

const scopeLine = moduleHint
  ? "  Scope DETECTED: module = \"" + moduleHint + "\" → CHỈ làm module này, KHÔNG drift sang module khác."
  : "  Scope: nếu user chỉ nêu 1 module/feature → CHỈ làm đúng module đó, KHÔNG auto-generate cho cả phase.";

// Required reads — step ①②③④ conditional on transcript scan
// Khi preload-qa-context đã fire → SKIP Section B (skill docs đã có trong context)
// Tiết kiệm ~2K tokens/prompt
let readsBlock;
if (qaPreloaded) {
  readsBlock = [
    "═══ B. REQUIRED READS — ✓ SKIP (QA context đã preloaded trong session) ═══",
    "  ① ✓ skills/test-quality-checklist/SKILL.md       (in preload context)",
    "  ② ✓ skills/qa-test-case/SKILL.md           (in preload context)",
    "  ③ ✓ skills/qa-test-case/common/skill docs  (in preload context — happy/bad/edge case)",
    "  Vẫn cần Read khi áp dụng cụ thể:",
    "    • skills/qa-test-case/common/{equivalence-partition,boundary-value,decision-table}.md (deep methods)",
    "    • skills/qa-test-case/backend/*.md OR frontend/*.md (test layer specific)",
    "    • docs/api/** hoặc test-design.md của story (Hierarchy of Truth #1)",
  ];
} else {
  const readsLines = [];
  if (!checklistRead) {
    readsLines.push(
      "  ① Read  skills/test-quality-checklist/SKILL.md   ★ ƯU TIÊN — chưa đọc trong session ★",
      "          (9 rules + 41 items — Rule #1 chống cho có, Rule #6 split P0/P1/P2, Rule #9 service signature)"
    );
  } else {
    readsLines.push(
      "  ① ✓ skills/test-quality-checklist/SKILL.md đã đọc trong session — skip."
    );
  }
  readsLines.push(
    "  ② Read  skills/qa-test-case/SKILL.md        (test design entry point)",
    "  ③ Read  skills/qa-test-case/common/{happy-case,bad-case,edge-case}.md",
    "  ④ Read  skills/qa-test-case/common/{equivalence-partition,boundary-value,decision-table}.md",
    "  ⑤ Read  skills/qa-test-case/backend/*.md (API) HOẶC frontend/*.md (E2E)",
    "  ⑥ Read  docs/api/** hoặc test-design doc của story (Hierarchy of Truth #1)"
  );
  readsBlock = ["═══ B. REQUIRED READS — trước khi Write spec ═══", ...readsLines];
}

const msg = [
  "🧪 TEST AUTOMATION ORCHESTRATION — phát hiện request liên quan viết test.",
  "",
  "═══ A. SCOPE DISCIPLINE (bắt buộc) ═══",
  scopeLine,
  "  Nếu user muốn whole-phase → user sẽ NÓI RÕ \"cả phase B\" / \"all modules\". Mặc định: 1 module.",
  "",
  ...readsBlock,
  "",
  "═══ C. RULE #6 — TEST ORGANIZATION (CRITICAL — split priority) ═══",
  "  ❌ SAI: 1 file chứa cả P0 + P1 + P2 (vd: phase-b-platform.spec.ts gộp 19 TCs)",
  "  ✅ ĐÚNG: tách file theo priority:",
  "       tests/api/{domain}/{story-folder}/P0-{feature}.spec.ts   ← Critical path",
  "       tests/api/{domain}/{story-folder}/P1-{feature}.spec.ts   ← Important",
  "       tests/api/{domain}/{story-folder}/P2-{feature}.spec.ts   ← Nice-to-have",
  "       tests/api/{domain}/{story-folder}/P3-{feature}.spec.ts   ← Perf/benchmark",
  "  Lý do: CI/CD chạy theo grep \"P0\" / \"P1\". Mix priority phá selective execution.",
  "  Ví dụ generic:  tests/api/{domain}/{story-folder}/",
  "                     ├── P0-{primary-feature}.spec.ts",
  "                     └── P1-{secondary-feature}.spec.ts",
  "",
  "═══ D. SERVICE + FACTORY DISCIPLINE (per-module, KHÔNG generic) ═══",
  "  ❌ SAI: <Domain>Service.create<Domain> (generic — không phản ánh module logic)",
  "  ✅ ĐÚNG: <SpecificEntity>Service.<specificAction> + create<SpecificEntity>Payload() (module-specific)",
  "  Workflow:",
  "    1. Grep src/{module-path}/ → tìm {feature}.service.ts + {feature}.factory.ts đã có",
  "    2. Nếu thiếu → tạo mới theo Module Creation Pattern (xem skills/qa-engineer/SKILL.md § Module Creation)",
  "    3. Import factory cho mọi payload (KHÔNG hard-code data)",
  "    4. Truyền testName param vào service call (cho logging traceability)",
  "",
  "═══ E. HIERARCHY OF TRUTH (khi BE bug) ═══",
  "  1. test-design / qa-test-case = requirement (cao nhất)",
  "  2. test code = verification",
  "  3. BE response = implementation (có thể bug)",
  "  4. API-DOC.md = documentation (có thể outdated)",
  "  → Test FAIL ≠ test sai. KHÔNG sửa test để pass khi BE wrong. Log bug theo template",
  "    docs/templates/log-bug-api-template.md (path do consumer config bug-tracking convention)",
  "",
  "═══ F. ERROR ASSERTION (typed contract) ═══",
  "  Import: parseErrorResponse, isApiErrorResponse, getApiErrorCode từ @src/utils/error-handler",
  "  Assert error.error.code match /^ERR_\\d+$/ (KHÔNG hardcode code cụ thể — BE có thể đổi)",
  "  Assert error.meta.requestId cho tracing",
  "",
  "═══ G. CHECKLIST trước khi mark task complete ═══",
  "  ☐ Files split theo P0/P1/P2 (Rule #6)",
  "  ☐ Mọi payload đi qua factory (Rule: parallel safety)",
  "  ☐ Mọi API call đi qua *.service.ts (KHÔNG request.post trực tiếp)",
  "  ☐ testName param truyền vào mọi service call",
  "  ☐ Endpoint từ API_ENDPOINTS (KHÔNG hardcode URL)",
  "  ☐ Import path dùng @src/* alias",
  "  ☐ 401/403 test: fresh context + *WithoutAuth() / dedicated test user login",
  "  ☐ ★ EXECUTE test với framework (Rule #10): detect Playwright/Jest/Vitest/... từ package.json",
  "      → run scope hẹp (file vừa viết, KHÔNG full suite), phân loại pass/fixme/skip theo Rule #8",
  "      → BÁO kết quả với evidence (vd: \"8 pass, 1 fixme ERR_4021, 0 fail\"), KHÔNG báo xong khi chưa run",
  "      → Hook run-test-mark-fixme.sh auto-fire PostToolUse, nhưng Claude vẫn PHẢI verify + summarize",
  "",
  "═══ H. OUTPUT TERSENESS (cost optimization) ═══",
  "  Pattern lãng phí cần TRÁNH (thinking out loud — recap đã làm gì):",
  "    ❌ \"Đã đọc đủ 3 technique docs. Áp dụng: Boundary ... → P0(0)...\" (recap thừa)",
  "    ❌ \"P2 thiếu parseErrorResponse... Sửa ngay\" (giải thích trước khi sửa)",
  "    ❌ \"Thư mục trống, sẵn sàng viết 3 file. Viết P0, P1, P2 song song.\" (narrate intent)",
  "    ❌ \"Cần xem scope của fixture X.\" (1 sentence thay vì 1 Read call)",
  "",
  "  ✅ Pattern đúng (≤50 tokens status, action-first):",
  "    \"Đọc service signature.\" → Read tool",
  "    \"Viết 3 file P0/P1/P2.\" → Write tools (song song)",
  "    \"Fix parseErr cho P2.\" → Edit tool",
  "",
  "  HARD RULES:",
  "    • Status message giữa actions: ≤50 tokens, KHÔNG recap đã làm gì",
  "    • KHÔNG narrate \"thinking out loud\" — action trước, explain SAU (chỉ khi user hỏi)",
  "    • Final summary: 1-2 sentences + file list. KHÔNG re-explain full strategy",
  "    • KHÔNG repeat hook context đã có trong additionalContext",
  "    • PARALLEL TOOL CALLS (CRITICAL): mọi Bash/Read/Grep/Glob/Edit ĐỘC LẬP gom vào 1 message",
  "      (1 assistant turn = N tool_use blocks). Observed: 23 sequential calls = $15.68/turn,",
  "      gom thành 5 parallel batches = -60% cost (~$6/turn saved).",
  "      ✅ Độc lập: đọc 5 file khác, grep 3 pattern, git status+diff+log",
  "      ❌ Tuần tự: call B cần output A (vd git rev-parse HEAD → git diff <SHA>)",
  "      Quy tắc: trước mỗi call hỏi \"cần output call trước không?\" → KHÔNG = gom chung",
  "",
  "Bypass: SKIP_TEST_ORCHESTRATION=1 (per-hook) hoặc SKIP_HOOKS=1 (master). Chỉ set khi đã review checklist.",
].join("\n");

const out = {
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: msg
  }
};
process.stdout.write(JSON.stringify(out));
' "$MODULE_HINT" "$CHECKLIST_READ" "$QA_PRELOADED")
printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="module=${MODULE_HINT:-?} checklist_read=$CHECKLIST_READ qa_preloaded=$QA_PRELOADED"

exit 0
