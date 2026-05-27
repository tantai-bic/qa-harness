#!/bin/bash
# PreToolUse hook: BLOCK Write|Edit của *.spec.ts / *.test.ts theo 4 gate layers.
#
# ─── Layer 1: BASELINE READS (mọi spec file) ────────────────────────────────
#   • docs/TEST-QUALITY-CHECKLIST.md     (9 rules — đặc biệt Rule #1/#2/#5/#6/#7)
#   • docs/qa-test-case/**/*.md          (ít nhất 1 file)
#
# ─── Layer 2: COVERAGE-BREADTH (khi filename gợi ý boundary/validation) ─────
#   Trigger: filename match /boundary|validation|P[12]-|edge/i
#   Require đọc ÍT NHẤT 2/3:
#     • docs/qa-test-case/common/boundary-value.md
#     • docs/qa-test-case/common/equivalence-partition.md
#     • docs/qa-test-case/common/decision-table.md
#
# ─── Layer 3: ERROR-PARSING-DEPTH (content-aware) ───────────────────────────
#   Trigger: write content có HttpStatus.BAD_REQUEST|UNAUTHORIZED|FORBIDDEN|
#            NOT_FOUND|CONFLICT|UNPROCESSABLE|TOO_MANY|INTERNAL_SERVER_ERROR
#   Require:
#     • Content phải dùng parseErrorResponse | isApiErrorResponse | getFieldErrorMessage
#       (validate error body shape — không chỉ check status code)
#     • Transcript phải Read src/types/error.types.ts + src/utils/error-handler.ts
#
# ─── Layer 4: FIXTURE-IMPORT + PATH-ALIAS (convention-adherence) ────────────
#   Đóng regression v2: với-hooks v1=1.0 → v2=0.70 vì LLM dùng @playwright/test.
#   Rule 4a: KHÔNG được `import { test } from "@playwright/test"` — phải từ @src/fixtures
#            (exempt: chỉ import `expect` từ @playwright/test thì OK)
#   Rule 4b: KHÔNG được dùng relative src import `from "../../../src/..."` — phải @src/* alias
#   Suggest: hook gợi ý fixture phù hợp dựa trên filename keyword (validation, phaseC, qa, ...)
#
# Trigger: tool_name = Write|Edit  AND  file_path match /\.(spec|test)\.[tj]sx?$/
# Output khi block: permissionDecision = "deny" + reason giải thích missing.
#
# Bypass: SKIP_QUALITY_CHECKLIST=1 (per-hook) hoặc SKIP_HOOKS=1 (master).

set -uo pipefail

SPAN_HOOK_NAME="enforce-test-quality-checklist"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_QUALITY_CHECKLIST:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_QUALITY_CHECKLIST"
  exit 0
fi

OUT=$(node -e '
const fs = require("fs");
const path = require("path");

let data;
try { data = JSON.parse(fs.readFileSync(0, "utf-8")); }
catch (e) { process.exit(0); }

const toolName = data.tool_name || "";
const filePath = (data.tool_input && data.tool_input.file_path) || "";
const transcriptPath = data.transcript_path || "";

// Chỉ enforce trên Write|Edit
if (!/^(Write|Edit)$/.test(toolName)) process.exit(0);

// Chỉ enforce trên test spec files
if (!/\.(spec|test)\.[tj]sx?$/i.test(filePath)) process.exit(0);

// Cần transcript để scan
if (!transcriptPath || !fs.existsSync(transcriptPath)) process.exit(0);

let transcript;
try { transcript = fs.readFileSync(transcriptPath, "utf-8"); }
catch (e) { process.exit(0); }

// Helper: build regex matching forward + backward slash path (Windows-safe).
// Chỉ thay slash giữa path segments — KHÔNG đụng slash trong character class.
const S = "[\\\\\\/]+";  // matches / or \\ (1 or more)

// Extract write content (Write.content hoặc Edit.new_string)
const writeContent = (data.tool_input && (data.tool_input.content || data.tool_input.new_string)) || "";
const fileBase = path.basename(filePath);

// ─── Layer 1: BASELINE READS ───────────────────────────────────────────────
const hasChecklist  = new RegExp("docs" + S + "TEST-QUALITY-CHECKLIST\\.md", "i").test(transcript);
const hasQaTestCase = new RegExp("docs" + S + "qa-test-case" + S + "[A-Za-z0-9_.\\-]+(?:" + S + "[A-Za-z0-9_.\\-]+)*\\.md", "i").test(transcript);

// ─── Layer 2: COVERAGE-BREADTH technique docs ───────────────────────────────
const isBoundaryFile = /(boundary|validation|edge|p[12]-)/i.test(fileBase);
const hasBoundaryDoc = new RegExp("qa-test-case" + S + "common" + S + "boundary-value\\.md", "i").test(transcript);
const hasEqPartDoc   = new RegExp("qa-test-case" + S + "common" + S + "equivalence-partition\\.md", "i").test(transcript);
const hasDecTableDoc = new RegExp("qa-test-case" + S + "common" + S + "decision-table\\.md", "i").test(transcript);
const techniqueCount = [hasBoundaryDoc, hasEqPartDoc, hasDecTableDoc].filter(Boolean).length;
const techniqueOK    = isBoundaryFile ? techniqueCount >= 2 : true;

// ─── Layer 3: ERROR-PARSING-DEPTH ───────────────────────────────────────────
const hasNegativeStatus = /HttpStatus\.(BAD_REQUEST|UNAUTHORIZED|FORBIDDEN|NOT_FOUND|CONFLICT|UNPROCESSABLE|TOO_MANY|INTERNAL_SERVER|GONE)/i.test(writeContent)
                       || /\bstatus\(\)\)\.toBe\((40[0-9]|41[0-9]|422|429|5\d\d)\b/.test(writeContent)
                       || /\.toContain\(\[?\s*HttpStatus\.[A-Z_]*(BAD|UNAUTH|FORBID|NOT_FOUND|CONFLICT)/i.test(writeContent);

const hasErrorParsing = /\b(parseErrorResponse|isApiErrorResponse|getFieldErrorMessage|getApiErrorCode|getApiErrorMessage|formatApiErrorForLog)\b/.test(writeContent);

const hasReadErrorTypes   = new RegExp("src" + S + "types" + S + "error\\.types", "i").test(transcript);
const hasReadErrorHandler = new RegExp("src" + S + "utils" + S + "error-handler", "i").test(transcript);

// Negative test PHẢI có error parsing (in content) + đọc error types/handler (in transcript)
const errorParsingOK = !hasNegativeStatus
  || (hasErrorParsing && hasReadErrorTypes && hasReadErrorHandler);

// ─── Layer 4: FIXTURE-IMPORT + PATH-ALIAS ───────────────────────────────────
// Rule 4a: import `test` từ @playwright/test → BLOCK (phải từ @src/fixtures)
//          Tách `test` riêng — `expect` từ @playwright/test vẫn OK
const importsTestFromPlaywright =
  /import\s*\{[^}]*\btest\b[^}]*\}\s*from\s*["\x27]@playwright\/test["\x27]/.test(writeContent);
const importsFromFixtures =
  /from\s+["\x27]@src\/fixtures(?:\/[^"\x27]+)?["\x27]/.test(writeContent);
const fixtureImportOK = !importsTestFromPlaywright || importsFromFixtures;

// Rule 4b: relative src import (../../src/..., ../src/...) → BLOCK
const relativeSrcImports = [...writeContent.matchAll(/from\s+["\x27]((?:\.\.\/)+src\/[^"\x27]+)["\x27]/g)]
  .map(m => m[1]);
const pathAliasOK = relativeSrcImports.length === 0;

// Suggest fixture file dựa trên filename keyword
function suggestFixture(filePath) {
  const fb = path.basename(filePath).toLowerCase();
  const map = [
    [/validat|platform|tactic|landing|duration|review/, "@src/fixtures/validation.fixture"],
    [/phase[-_]?c|goal\b|campaign-goal/,                "@src/fixtures/phaseC.fixture"],
    [/phase[-_]?d|delivery|process-update/,             "@src/fixtures/phaseD.fixture"],
    [/refinement|q[1-7]|contextual/,                    "@src/fixtures/refinement.fixture"],
    [/campaign-qa|q[-_]?and[-_]?a|backer-question/,     "@src/fixtures/campaign-qa.fixture"],
    [/profile|me\b|my-profile/,                         "@src/fixtures/profile.fixture"],
    [/login|signup|auth|guest-session/,                 "@src/fixtures/login.fixture"],
    [/guest(?!-session)/,                               "@src/fixtures/guest.fixture"],
    [/dashboard|analytic/,                              "@src/fixtures/e2e-dashboard.fixture"],
    [/hero-media.*phase[-_]?b/,                         "@src/fixtures/e2e-hero-media-phase-b.fixture"],
    [/hero-media.*phase[-_]?c/,                         "@src/fixtures/e2e-hero-media-phase-c.fixture"],
    [/landing-page-editor/,                             "@src/fixtures/e2e-landing-page-editor.fixture"],
    [/landing-page/,                                    "@src/fixtures/e2e-landing-page.fixture"],
    [/campaign-editor/,                                 "@src/fixtures/e2e-campaign-editor.fixture"],
    [/campaign-setting/,                                "@src/fixtures/e2e-campaign-settings.fixture"],
    [/publish-modal/,                                   "@src/fixtures/e2e-publish-modal.fixture"],
    [/share-link/,                                      "@src/fixtures/e2e-share-link.fixture"],
    [/email-survey/,                                    "@src/fixtures/e2e-email-survey.fixture"],
  ];
  for (const [re, fx] of map) if (re.test(fb)) return fx;
  return "@src/fixtures";  // merged hub fallback
}

// ─── Aggregate decision ─────────────────────────────────────────────────────
if (hasChecklist && hasQaTestCase && techniqueOK && errorParsingOK && fixtureImportOK && pathAliasOK) process.exit(0);

const missing = [];

if (!hasChecklist) {
  missing.push({
    layer: "L1 BASELINE",
    item: "docs/TEST-QUALITY-CHECKLIST.md  (9 rules + 41 items)"
  });
}
if (!hasQaTestCase) {
  missing.push({
    layer: "L1 BASELINE",
    item: "docs/qa-test-case/skill.md      (test design entry point)"
  });
}
if (isBoundaryFile && !techniqueOK) {
  const need = [];
  if (!hasBoundaryDoc) need.push("docs/qa-test-case/common/boundary-value.md");
  if (!hasEqPartDoc)   need.push("docs/qa-test-case/common/equivalence-partition.md");
  if (!hasDecTableDoc) need.push("docs/qa-test-case/common/decision-table.md");
  missing.push({
    layer: "L2 COVERAGE-BREADTH",
    item: "Đọc ÍT NHẤT 2/3 technique doc (file boundary/validation/edge/P[12]-):\n     " + need.map(p => "• " + p).join("\n     ")
  });
}
if (hasNegativeStatus) {
  const errSub = [];
  if (!hasErrorParsing) {
    errSub.push("Content KHÔNG dùng parseErrorResponse / isApiErrorResponse / getFieldErrorMessage —");
    errSub.push("đang assert negative status (400/401/403/404...) MÀ chỉ check response.status()");
    errSub.push("→ thiếu error body shape validation (score error-parsing-depth tụt mạnh)");
    errSub.push("");
    errSub.push("Fix code:");
    errSub.push("```typescript");
    errSub.push("expect(response.status()).toBe(HttpStatus.BAD_REQUEST);");
    errSub.push("const err = await parseErrorResponse(response);");
    errSub.push("if (isApiErrorResponse(err)) {");
    errSub.push("  expect(err).toHaveProperty(\"success\", false);");
    errSub.push("  const msg = getFieldErrorMessage(err, \"fieldName\") ?? getApiErrorMessage(err);");
    errSub.push("  expect(msg).toMatch(/expected-keyword/);");
    errSub.push("}");
    errSub.push("```");
  }
  if (!hasReadErrorTypes)   errSub.push("• MISSING Read: src/types/error.types.ts");
  if (!hasReadErrorHandler) errSub.push("• MISSING Read: src/utils/error-handler.ts");
  if (errSub.length) {
    missing.push({
      layer: "L3 ERROR-PARSING-DEPTH",
      item: errSub.join("\n     ")
    });
  }
}

if (!fixtureImportOK) {
  const suggested = suggestFixture(filePath);
  missing.push({
    layer: "L4 FIXTURE-IMPORT",
    item: [
      "Content import `test` từ @playwright/test — VI PHẠM project rule",
      "(project-context.md: \"ALWAYS use auto-cleanup fixtures via @src/fixtures\")",
      "",
      "Fix:",
      "```typescript",
      "// ❌ SAI",
      "import { test, expect } from \x27@playwright/test\x27;",
      "",
      "// ✅ ĐÚNG — fixture phù hợp với filename:",
      "import { test, expect } from \x27" + suggested + "\x27;",
      "```",
      "",
      "Available fixtures: ls src/fixtures/*.ts (28 file).",
      "Merged hub @src/fixtures (index.ts) gồm: testUser, session, login, stealth.",
      "Module-specific fixture cung cấp mockCampaign + auto-cleanup phù hợp domain."
    ].join("\n     ")
  });
}

if (!pathAliasOK) {
  missing.push({
    layer: "L4 PATH-ALIAS",
    item: [
      "Content dùng relative src import — VI PHẠM project rule (project-context.md § IMPORT PATTERNS).",
      "",
      "Violations (" + relativeSrcImports.length + "):"
    ].concat(
      relativeSrcImports.slice(0, 5).map(p => "  • from \"" + p + "\"  →  from \"@src/" + p.replace(/^(?:\.\.\/)+src\//, "") + "\"")
    ).concat([
      relativeSrcImports.length > 5 ? "  • ... (+" + (relativeSrcImports.length - 5) + " more)" : "",
      "",
      "Lý do: @src/* alias làm test portable khi refactor — relative path break khi di chuyển file."
    ]).filter(Boolean).join("\n     ")
  });
}

const reason = [
  "🚧 TEST QUALITY GATE — BLOCK " + toolName + " " + fileBase,
  "",
  "Spec chưa pass quality gates. Missing:",
  "",
  ...missing.map(m => "▸ [" + m.layer + "] " + m.item),
  "",
  "═══ Vì sao block ═══",
  "Hook A/B test (v1 → v2) cho thấy score drift:",
  "  • coverage-breadth:    0.65 → 0.92  (+0.27) ← Layer 2 đã fix",
  "  • error-parsing-depth: 0.40 → 0.95  (+0.55) ← Layer 3 đã fix",
  "  • convention-adherence: 1.00 → 0.70 (-0.30 regression) ← Layer 4 fix lần này",
  "→ Hook ép: read technique docs + dùng error parsing utils + import test từ @src/fixtures.",
  "",
  "═══ Action ═══",
  "1. Read các file MISSING (parallel cho speed)",
  "2. Sửa content nếu thiếu parseErrorResponse / isApiErrorResponse",
  "3. Retry " + toolName + " — hook pass khi đủ evidence + đúng pattern",
  "",
  "Bypass (nếu thực sự cần): SKIP_QUALITY_CHECKLIST=1 hoặc SKIP_HOOKS=1",
].join("\n");

const out = {
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: reason
  }
};
process.stdout.write(JSON.stringify(out));
' <<< "$INPUT" 2>/dev/null)

if [[ -n "$OUT" ]]; then
  printf '%s' "$OUT"
  SPAN_DECISION="deny"
  SPAN_BYTES=${#OUT}
  FP=$(printf '%s' "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/' | tr -d '
	')
  SPAN_DETAIL="file=$(basename "$FP" 2>/dev/null || echo "$FP")"
fi
# else: SPAN_DECISION stays "skip"

exit 0
