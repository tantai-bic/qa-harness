#!/bin/bash
# SessionStart hook: check consumer đã setup folder convention + toolchain
# packages bắt buộc chưa.
#
# Khi consumer install plugin lần đầu, missing nhiều setup → hook nhắc trong
# session đầu tiên (matcher=startup). KHÔNG fire khi resume/clear/compact để
# tránh nhiễu.
#
# Default required paths:
#   _bmad/bmm/config.yaml                            BMAD config
#   docs/roadmap/README.md                           Roadmap index
#   docs/templates/log-bug-api-template.md           Bug log template
#   package.json                                     Project manifest
#   playwright.config.ts|.js                         Playwright config
#   src/constants/api.constants.ts                   Endpoints
#   src/fixtures/                                    Fixture dir
#   src/pages | src/page-objects | tests/pages       POM (Page Object Model)
#   src/components | src/component-objects           COM (Component Object Model)
#   src/helpers | src/utils                          Helper functions
#   src/factories | src/data-factories               Data Factory
#   tests/                                           Test dir
#
# Default required packages (declared trong package.json deps/devDeps):
#   playwright (or @playwright/test)                 Test runner
#   husky                                            Git hooks
#   lint-staged                                      Format-on-commit
#   eslint                                           Linter
#   prettier                                         Formatter
#
# Playwright browser binary install (`npx playwright install`) INTENTIONALLY
# skipped — hook chỉ in reminder khi playwright declared. Reason: install browser
# tốn thời gian + bandwidth, để user tự chạy khi sẵn sàng.
#
# Detection strategy: check declared trong package.json (deps/devDeps), KHÔNG
# stat node_modules/<pkg>. Lý do: Yarn PnP không có node_modules, pnpm với
# `shamefully-hoist=false` đặt package ở `node_modules/.pnpm/...`. Declared
# check tránh false-negative trên các package manager đó (Devil's Advocate
# must-fix #2,#3). Trade-off: declared-but-corrupt install không detect được —
# user phát hiện khi chạy test.
#
# Consumer customization:
#   - Bổ sung paths qua env CONSUMER_REQUIRED_PATHS (newline-separated, support
#     relative path + alternation via "|" — last 2 fields luôn là label|desc).
#       Vd: CONSUMER_REQUIRED_PATHS=$'docs/api/\ntsconfig.json'
#   - Loại bỏ default paths qua CONSUMER_SETUP_SKIP_DEFAULTS=1
#   - Bypass: SKIP_SETUP_CHECK=1 (per-hook) hoặc SKIP_HOOKS=1 (master)
#
# Run cadence: hook fire mỗi session startup. Khi cả paths + packages clean,
# silent exit (no token cost). KHÔNG dùng per-project flag file để tránh các
# vấn đề: commit nhầm vào git, worktree fragmentation, `git clean -fdx` reset.
#
# Per CLAUDE.md: node -e (jq không có trên Windows Git Bash).

set -uo pipefail

SPAN_HOOK_NAME="check-consumer-setup"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_SETUP_CHECK:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_SETUP_CHECK"
  exit 0
fi

# Only fire on cold startup — skip resume/clear/compact để tránh remind lặp
SOURCE=$(node -e '
try {
  const i = JSON.parse(require("fs").readFileSync(0, "utf-8"));
  process.stdout.write(i.source || "");
} catch { process.exit(0); }
' <<< "$INPUT" 2>/dev/null)

if [[ "$SOURCE" != "startup" ]]; then
  SPAN_DECISION="skip"
  SPAN_DETAIL="source=$SOURCE"
  exit 0
fi

# Self-detection: nếu đang chạy trên plugin source itself (có
# .claude-plugin/plugin.json với "bmad-harness-plugin" name) → skip.
# Plugin source không cần check consumer setup cho chính nó.
if [[ -f ".claude-plugin/plugin.json" ]]; then
  if grep -q '"name"[[:space:]]*:[[:space:]]*"bmad-harness-plugin"' .claude-plugin/plugin.json 2>/dev/null; then
    SPAN_DECISION="skip"
    SPAN_DETAIL="plugin-self"
    exit 0
  fi
fi

# ─── Build required paths list ──────────────────────────────────────────────
DEFAULT_PATHS=(
  "_bmad/bmm/config.yaml|BMAD config|consumer phải set project_name, user_name, communication_language"
  "docs/roadmap/README.md|Roadmap index|cần cho enforce-roadmap-reading hook discovery"
  "docs/templates/log-bug-api-template.md|Bug log template|cho hierarchy of truth — log BE bug, không sửa test"
  "package.json|NPM manifest|Playwright + TS dependencies"
  "playwright.config.ts|playwright.config.js|Playwright config|timeouts, projects, retries"
  "src/constants/api.constants.ts|API_ENDPOINTS|endpoint constants — KHÔNG hardcode URL"
  "src/fixtures|Fixture dir|auto-cleanup fixtures (Rule 4a — import test từ @src/fixtures)"
  "src/pages|src/page-objects|tests/pages|POM (Page Object Model)|page abstractions — encapsulate selectors + actions"
  "src/components|src/component-objects|COM (Component Object Model)|reusable component fragments (login form, nav, modal)"
  "src/helpers|src/utils|Helper functions|API/E2E helpers (parseErrorResponse, *WithoutAuth, response asserts)"
  "src/factories|src/data-factories|Data Factory|parallel-safe payload factories (createXPayload — Rule 3)"
  "tests|Test dir|tests/api/, tests/e2e/"
)

MISSING_JSON=$(node -e '
const fs = require("fs");
const path = require("path");

const defaults = process.env.CONSUMER_SETUP_SKIP_DEFAULTS === "1" ? [] :
  process.argv.slice(1);
const extras = (process.env.CONSUMER_REQUIRED_PATHS || "")
  .split(/\r?\n/).map(s => s.trim()).filter(Boolean);

const all = [...defaults, ...extras.map(p => p + "|(custom path)|consumer-defined")];
const missing = [];

for (const entry of all) {
  const parts = entry.split("|");
  // Format: "path1|...|pathN|label|desc" — last 2 fields luôn là label|desc,
  // các field còn lại là candidates (accept any match). Min 3 fields.
  // Edge case length <3 → bare path, no label/desc.
  let candidates, label, desc;
  if (parts.length >= 3) {
    candidates = parts.slice(0, -2);
    label = parts[parts.length - 2];
    desc  = parts[parts.length - 1];
  } else {
    candidates = [parts[0]];
    label = parts[1] || parts[0];
    desc  = "";
  }
  const found = candidates.some(c => {
    try { return fs.existsSync(path.resolve(process.cwd(), c)); } catch { return false; }
  });
  if (!found) missing.push({ candidates, label, desc });
}

process.stdout.write(JSON.stringify(missing));
' "${DEFAULT_PATHS[@]}" 2>/dev/null)

MISSING_COUNT=$(node -e '
const m = JSON.parse(process.argv[1] || "[]");
process.stdout.write(String(m.length));
' "$MISSING_JSON" 2>/dev/null)

# ─── Check required packages (declared in package.json) ─────────────────────
# Strategy: chỉ check declared trong deps/devDeps. KHÔNG stat node_modules để
# tránh false-negative trên Yarn PnP / pnpm shamefully-hoist=false (Devil's
# Advocate must-fix #2,#3). Khi package.json missing → silent return [].
MISSING_PACKAGES_JSON=$(node -e '
const fs = require("fs");
const required = [
  { key: "playwright",  aliases: ["playwright", "@playwright/test"] },
  { key: "husky",       aliases: ["husky"] },
  { key: "lint-staged", aliases: ["lint-staged"] },
  { key: "eslint",      aliases: ["eslint"] },
  { key: "prettier",    aliases: ["prettier"] },
];
let pkg;
try { pkg = JSON.parse(fs.readFileSync("package.json", "utf-8")); }
catch { process.stdout.write("[]"); process.exit(0); }
const all = { ...(pkg.dependencies || {}), ...(pkg.devDependencies || {}) };
const missing = required
  .filter(r => !r.aliases.some(a => all[a]))
  .map(r => ({ key: r.key, aliases: r.aliases }));
process.stdout.write(JSON.stringify(missing));
' 2>/dev/null)

MISSING_PACKAGES_COUNT=$(node -e '
const m = JSON.parse(process.argv[1] || "[]");
process.stdout.write(String(m.length));
' "$MISSING_PACKAGES_JSON" 2>/dev/null)

# Playwright declared? — chỉ in browser-install reminder nếu có
PLAYWRIGHT_DECLARED=$(node -e '
try {
  const p = JSON.parse(require("fs").readFileSync("package.json", "utf-8"));
  const all = { ...(p.dependencies || {}), ...(p.devDependencies || {}) };
  process.stdout.write((all["playwright"] || all["@playwright/test"]) ? "1" : "0");
} catch { process.stdout.write("0"); }
' 2>/dev/null)

if [[ "${MISSING_COUNT:-0}" == "0" && "${MISSING_PACKAGES_COUNT:-0}" == "0" ]]; then
  SPAN_DECISION="skip"
  SPAN_DETAIL="all-checks-pass"
  exit 0
fi

# ─── Emit additionalContext JSON ────────────────────────────────────────────
OUT=$(node -e '
const missing = JSON.parse(process.argv[1] || "[]");
const missingPkgs = JSON.parse(process.argv[2] || "[]");
const playwrightDeclared = process.argv[3] === "1";

const pathItems = missing.map((m, i) => {
  const pathStr = m.candidates.length > 1
    ? m.candidates.map(c => "`" + c + "`").join(" hoặc ")
    : "`" + m.candidates[0] + "`";
  return "  " + (i+1) + ". " + pathStr + " — " + m.label + "\n     " + (m.desc || "");
}).join("\n");

const pkgItems = missingPkgs.map((p, i) => {
  const aliasNote = p.aliases.length > 1
    ? " [alias chấp nhận: " + p.aliases.join(" / ") + "]"
    : "";
  return "  " + (i+1) + ". `" + p.key + "`" + aliasNote +
    " — chưa khai báo trong package.json (deps/devDeps)";
}).join("\n");

const total = missing.length + missingPkgs.length;
const sections = [];
if (missing.length > 0) {
  sections.push("📁 Path/Folder convention (" + missing.length + " thiếu):\n\n" + pathItems);
}
if (missingPkgs.length > 0) {
  sections.push("📦 Package toolchain (" + missingPkgs.length + " thiếu):\n\n" + pkgItems);
}

const lines = [
  "🛠️  CONSUMER SETUP CHECK — phát hiện " + total + " mục bắt buộc chưa có.",
  "",
  "Plugin bmad-harness-plugin yêu cầu consumer setup tối thiểu để hooks/skills hoạt động đầy đủ:",
  "",
  sections.join("\n\n"),
  "",
  "═══ Hướng dẫn ═══",
  "  • Cài thiếu package: npm i -D <pkg>  (hoặc yarn add -D / pnpm add -D / bun add -d)",
  "  • Tạo folder convention — tham khảo skills/qa-engineer/architecture.md § 10 Directory Structure",
  "  • Sau khi fix xong, restart Claude session để hook re-check",
  "",
  "Capability bị degrade theo từng item missing:",
  "  • _bmad/bmm/config.yaml             → BMAD agents activation fail",
  "  • docs/roadmap/                     → enforce-roadmap-reading silent (no roadmap to suggest)",
  "  • src/constants/api.constants.ts    → test vi phạm Rule: hardcode URL",
  "  • src/fixtures/                     → spec không import @src/fixtures (Rule 4a)",
  "  • src/pages, src/components         → qa-engineer skill kỳ vọng POM/COM layout",
  "  • src/helpers, src/factories        → helper + factory pattern (Rule 3) bị vi phạm",
  "  • playwright / husky / lint-staged  → CI gate (test runner + format-on-commit) hỏng",
  "  • eslint / prettier                 → code quality enforcement off",
];

if (playwrightDeclared) {
  lines.push(
    "",
    "› Lưu ý: hook KHÔNG tự cài browser binary cho Playwright.",
    "  Khi nào sẵn sàng chạy test, nhớ:  npx playwright install",
    "  (skip cũng được, Playwright sẽ tự nhắc khi launch browser lần đầu)"
  );
}

lines.push(
  "",
  "Bypass: SKIP_SETUP_CHECK=1 (per-hook) hoặc SKIP_HOOKS=1 (master).",
  "Tuỳ biến: CONSUMER_REQUIRED_PATHS (newline) thêm path; CONSUMER_SETUP_SKIP_DEFAULTS=1 bỏ defaults."
);

const out = {
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: lines.join("\n")
  }
};
process.stdout.write(JSON.stringify(out));
' "$MISSING_JSON" "$MISSING_PACKAGES_JSON" "$PLAYWRIGHT_DECLARED")

printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="missing-paths=$MISSING_COUNT,missing-pkgs=$MISSING_PACKAGES_COUNT"

exit 0
