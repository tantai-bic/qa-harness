#!/bin/bash
# PreToolUse hook: BLOCK Write|Edit của *.spec.ts / *.test.ts theo 4 gate layers.
#
# ─── Layer 1: BASELINE READS (mọi spec file) ────────────────────────────────
#   • skills/test-quality-checklist/SKILL.md     (9 rules — đặc biệt Rule #1/#2/#5/#6/#7)
#   • skills/qa-test-case/**/*.md          (ít nhất 1 file)
#
# ─── Layer 2: COVERAGE-BREADTH (khi filename gợi ý boundary/validation) ─────
#   Trigger: filename match /boundary|validation|P[12]-|edge/i
#   Require đọc ÍT NHẤT 2/3:
#     • skills/qa-test-case/common/boundary-value.md
#     • skills/qa-test-case/common/equivalence-partition.md
#     • skills/qa-test-case/common/decision-table.md
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
#   Suggest: hook gợi ý fixture path dựa trên feature word inferred từ filename;
#            consumer override via env FIXTURE_MAP_JSON
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
const hasChecklist  = new RegExp("skills" + S + "test-quality-checklist" + S + "SKILL\\.md", "i").test(transcript);
const hasQaTestCase = new RegExp("skills" + S + "qa-test-case" + S + "[A-Za-z0-9_.\\-]+(?:" + S + "[A-Za-z0-9_.\\-]+)*\\.md", "i").test(transcript);

// ─── Layer 2: COVERAGE-BREADTH technique docs ───────────────────────────────
const isBoundaryFile = /(boundary|validation|edge|p[12]-)/i.test(fileBase);
const hasBoundaryDoc = new RegExp("qa-test-case" + S + "common" + S + "boundary-value\\.md", "i").test(transcript);
const hasEqPartDoc   = new RegExp("qa-test-case" + S + "common" + S + "equivalence-partition\\.md", "i").test(transcript);
const hasDecTableDoc = new RegExp("qa-test-case" + S + "common" + S + "decision-table\\.md", "i").test(transcript);
// (qa-test-case path matches both legacy docs/qa-test-case/ và new skills/qa-test-case/ vì regex bắt từ "qa-test-case" trở đi)
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

// Suggest fixture path dựa trên filename — generic: extract feature word từ tên file.
// Consumer có thể inject mapping cụ thể qua env var FIXTURE_MAP_JSON
// (JSON shape: [[regex_string, fixture_path], ...]) — vd:
//   FIXTURE_MAP_JSON=\x27[["validat|platform","@src/fixtures/validation.fixture"]]\x27
function suggestFixture(filePath) {
  const fb = path.basename(filePath).toLowerCase();
  const userMap = (() => {
    try { return JSON.parse(process.env.FIXTURE_MAP_JSON || "[]"); }
    catch { return []; }
  })();
  for (const [reStr, fx] of userMap) {
    try { if (new RegExp(reStr, "i").test(fb)) return fx; } catch {}
  }
  // Generic inference: strip P{n}- prefix + .spec.ts suffix → feature slug
  const slug = fb.replace(/^p[0-9]-/i, "").replace(/\.(spec|test)\.[tj]sx?$/i, "");
  const feature = slug.split(/[-._]/).filter(Boolean)[0];
  return feature ? "@src/fixtures/" + feature + ".fixture" : "@src/fixtures";
}

// ─── Aggregate decision ─────────────────────────────────────────────────────
if (hasChecklist && hasQaTestCase && techniqueOK && errorParsingOK && fixtureImportOK && pathAliasOK) process.exit(0);

const missing = [];

if (!hasChecklist) {
  missing.push({
    layer: "L1 BASELINE",
    item: "skills/test-quality-checklist/SKILL.md  (9 rules + 41 items)"
  });
}
if (!hasQaTestCase) {
  missing.push({
    layer: "L1 BASELINE",
    item: "skills/qa-test-case/SKILL.md      (test design entry point)"
  });
}
if (isBoundaryFile && !techniqueOK) {
  const need = [];
  if (!hasBoundaryDoc) need.push("skills/qa-test-case/common/boundary-value.md");
  if (!hasEqPartDoc)   need.push("skills/qa-test-case/common/equivalence-partition.md");
  if (!hasDecTableDoc) need.push("skills/qa-test-case/common/decision-table.md");
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
      "Content import `test` từ @playwright/test — VI PHẠM rule",
      "(harness convention: ALWAYS use auto-cleanup fixtures via @src/fixtures)",
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
      "Available fixtures: ls src/fixtures/*.ts.",
      "Mỗi fixture cung cấp setup + auto-cleanup cho domain tương ứng.",
      "Inject mapping cụ thể qua env FIXTURE_MAP_JSON nếu cần override default inference."
    ].join("\n     ")
  });
}

if (!pathAliasOK) {
  missing.push({
    layer: "L4 PATH-ALIAS",
    item: [
      "Content dùng relative src import — VI PHẠM rule (harness convention: dùng @src/* alias).",
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
  "4-layer gate ép: baseline reads (L1) + technique coverage (L2) + error parsing depth (L3) +",
  "fixture import + path alias (L4). Mỗi layer chống một class regression đã observed:",
  "  L1: spec viết khi không đọc rules → vi phạm Rule #1/#5/#6",
  "  L2: boundary/validation file không đọc 3 technique docs → coverage hep",
  "  L3: negative test chỉ check status, không assert error body shape → parsing depth thấp",
  "  L4: import test từ @playwright/test → mất auto-cleanup; relative src import → break refactor",
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
