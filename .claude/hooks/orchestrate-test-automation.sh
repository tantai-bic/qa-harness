#!/bin/bash
# UserPromptSubmit hook: orchestrate test automation workflow.
#
# Trigger khi user prompt liên quan viết / tạo / generate test automation.
# Emit reminder về:
#   - Scope discipline: KHÔNG drift sang module khác (chỉ làm đúng module user hỏi)
#   - Per-module workflow: Service + Factory đúng module (KHÔNG generic)
#   - Rule #6 (TEST-QUALITY-CHECKLIST.md): SPLIT P0 / P1 / P2 vào file RIÊNG
#   - Hierarchy of Truth: test-design → test code → BE → API-DOC
#   - Required reads: TEST-QUALITY-CHECKLIST.md + docs/qa-test-case/**
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

# Scan transcript: TEST-QUALITY-CHECKLIST.md đã đọc trong session chưa?
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
  if grep -qE 'TEST-QUALITY-CHECKLIST\.md' "$TRANSCRIPT_PATH" 2>/dev/null; then
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

# ─── Module hint extraction (best effort) ───────────────────────────────────
MODULE_HINT=""
for KW in platform tactics tactic landing-page landing landingpage duration review \
          refinement goal pledge delivery refund escrow dispute withdrawal \
          campaign-editor campaign-page campaign-goal campaign-update \
          hero-media discovery profile checkout q-and-a qa-module \
          dashboard validation conversion-trend pledges-timeline tier-distribution; do
  if echo "$LC_PROMPT" | grep -qE "\b${KW}\b|${KW//-/[-_ ]?}"; then
    MODULE_HINT="$KW"
    break
  fi
done

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
    "  ① ✓ docs/TEST-QUALITY-CHECKLIST.md       (in preload context)",
    "  ② ✓ docs/qa-test-case/skill.md           (in preload context)",
    "  ③ ✓ docs/qa-test-case/common/skill docs  (in preload context — happy/bad/edge case)",
    "  Vẫn cần Read khi áp dụng cụ thể:",
    "    • docs/qa-test-case/common/{equivalence-partition,boundary-value,decision-table}.md (deep methods)",
    "    • docs/qa-test-case/backend/*.md OR frontend/*.md (test layer specific)",
    "    • docs/api/** hoặc test-design.md của story (Hierarchy of Truth #1)",
  ];
} else {
  const readsLines = [];
  if (!checklistRead) {
    readsLines.push(
      "  ① Read  docs/TEST-QUALITY-CHECKLIST.md   ★ ƯU TIÊN — chưa đọc trong session ★",
      "          (9 rules + 41 items — Rule #1 chống cho có, Rule #6 split P0/P1/P2, Rule #9 service signature)"
    );
  } else {
    readsLines.push(
      "  ① ✓ docs/TEST-QUALITY-CHECKLIST.md đã đọc trong session — skip."
    );
  }
  readsLines.push(
    "  ② Read  docs/qa-test-case/skill.md        (test design entry point)",
    "  ③ Read  docs/qa-test-case/common/{happy-case,bad-case,edge-case}.md",
    "  ④ Read  docs/qa-test-case/common/{equivalence-partition,boundary-value,decision-table}.md",
    "  ⑤ Read  docs/qa-test-case/backend/*.md (API) HOẶC frontend/*.md (E2E)",
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
  "  Ví dụ chuẩn (Epic 05.3): tests/api/campaign/phase-d/process-update/story-05.3.5-like-reactions/",
  "                              ├── P0-toggle-like.spec.ts",
  "                              └── P1-idempotency.spec.ts",
  "",
  "═══ D. SERVICE + FACTORY DISCIPLINE (per-module, KHÔNG generic) ═══",
  "  ❌ SAI: ValidationService.createValidation (generic — không phản ánh module logic)",
  "  ✅ ĐÚNG: PlatformService.saveValidation + createAllPlatformsPayload() (module-specific)",
  "  Workflow:",
  "    1. Grep src/{module-path}/ → tìm {feature}.service.ts + {feature}.factory.ts đã có",
  "    2. Nếu thiếu → tạo mới theo Module Creation Pattern (project-context.md § \"NEW MODULE CREATION\")",
  "    3. Import factory cho mọi payload (KHÔNG hard-code data)",
  "    4. Truyền testName param vào service call (cho logging traceability)",
  "",
  "═══ E. HIERARCHY OF TRUTH (khi BE bug) ═══",
  "  1. test-design / qa-test-case = requirement (cao nhất)",
  "  2. test code = verification",
  "  3. BE response = implementation (có thể bug)",
  "  4. API-DOC.md = documentation (có thể outdated)",
  "  → Test FAIL ≠ test sai. KHÔNG sửa test để pass khi BE wrong. Log bug theo template",
  "    docs/templates/log-bug-api-template.md → docs/sprint{N}/squad-{name}/story/story-{ID}/",
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
  "  ☐ 401/403 test: fresh context + *WithoutAuth() / TEST_USER1 login",
  "",
  "═══ H. OUTPUT TERSENESS (cost optimization) ═══",
  "  Đo observed: trace 89fee3f7 đã waste ~$0.90 (12K tokens) cho \"thinking out loud\".",
  "  Vd các pattern lãng phí cần TRÁNH:",
  "    ❌ \"Đã đọc đủ 3 technique docs. Áp dụng: Boundary platforms 0,1,2,5,6,7 → P0(0)...\" (3859 tokens)",
  "    ❌ \"P2 thiếu parseErrorResponse... Sửa ngay\" (3176 tokens recap)",
  "    ❌ \"Thư mục trống, sẵn sàng viết 3 file. Viết P0, P1, P2 song song.\" (2422 tokens)",
  "    ❌ \"Cần xem scope của mockCampaign fixture.\" (1387 tokens cho 1 intent)",
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
