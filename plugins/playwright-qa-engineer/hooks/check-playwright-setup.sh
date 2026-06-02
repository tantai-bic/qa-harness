#!/bin/bash
# SessionStart hook: check consumer đã setup Playwright project structure + toolchain
# packages bắt buộc chưa.
#
# Khi consumer install plugin lần đầu, missing nhiều setup → hook nhắc trong
# session đầu tiên (matcher=startup). KHÔNG fire khi resume/clear/compact để
# tránh nhiễu.
#
# Default required paths (base project structure only):
#   package.json                                     Project manifest
#   playwright.config.ts|.js                         Playwright config
#   tests/                                           Test dir
#
# Plugin-specific checks are handled by each plugin's own check-setup.sh:
#   bmad-workflows  → _bmad/bmm/config.yaml, docs/roadmap/, docs/templates/
#   test-enforcement → src/fixtures/, src/pages/, src/components/, src/helpers/, src/factories/, src/constants/
#   observability    → LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY
#
# Default required packages (declared trong package.json deps/devDeps):
#   @playwright/test                                 Playwright test framework
#   lint-staged                                      Format-on-commit
#   eslint                                           Linter
#   prettier                                         Formatter
#
# Detection strategy: check declared trong package.json (deps/devDeps), KHÔNG
# stat node_modules/<pkg>. Lý do: Yarn PnP không có node_modules, pnpm với
# `shamefully-hoist=false` đặt package ở `node_modules/.pnpm/...`. Declared
# check tránh false-negative trên các package manager đó. Trade-off:
# declared-but-corrupt install không detect được — user phát hiện khi chạy test.
#
# Consumer customization:
#   - Bổ sung paths qua env CONSUMER_REQUIRED_PATHS (newline-separated, support
#     relative path + alternation via "|" — last 2 fields luôn là label|desc).
#       Vd: CONSUMER_REQUIRED_PATHS=$'docs/api/\ntsconfig.json'
#   - Loại bỏ default paths qua CONSUMER_SETUP_SKIP_DEFAULTS=1
#   - Bypass: SKIP_PLAYWRIGHT_SETUP=1 / SKIP_SETUP_CHECK=1 (per-hook) hoặc SKIP_HOOKS=1 (master)
#
# Run cadence: hook fire mỗi session startup. Khi cả paths + packages clean,
# silent exit (no token cost). KHÔNG dùng per-project flag file để tránh các
# vấn đề: commit nhầm vào git, worktree fragmentation, `git clean -fdx` reset.
#
# Per CLAUDE.md: node -e (jq không có trên Windows Git Bash).

set -uo pipefail

SPAN_HOOK_NAME="check-playwright-setup"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

# SKIP_PLAYWRIGHT_SETUP=1 (new) hoặc SKIP_SETUP_CHECK=1 (legacy alias)
if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_PLAYWRIGHT_SETUP:-0}" == "1" || "${SKIP_SETUP_CHECK:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  if [[ "${SKIP_HOOKS:-0}" == "1" ]]; then
    SPAN_BYPASS="SKIP_HOOKS"
  elif [[ "${SKIP_PLAYWRIGHT_SETUP:-0}" == "1" ]]; then
    SPAN_BYPASS="SKIP_PLAYWRIGHT_SETUP"
  else
    SPAN_BYPASS="SKIP_SETUP_CHECK"
  fi
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
  "package.json|NPM manifest|Playwright + TS dependencies"
  "playwright.config.ts|playwright.config.js|Playwright config|timeouts, projects, retries"
  "tsconfig.json|TypeScript config|narrow scope: src/ + tests/ + playwright.config.ts"
  "tests|Test dir|tests/api/, tests/e2e/"
  ".husky|Husky hooks dir|Git hooks managed by husky (chạy lint-staged on commit)"
  ".husky/pre-commit|Husky pre-commit hook|Required: chạy lint-staged hoặc test trước commit"
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
# tránh false-negative trên Yarn PnP / pnpm shamefully-hoist=false.
# Khi package.json missing → silent return [].
MISSING_PACKAGES_JSON=$(node -e '
const fs = require("fs");
const required = [
  { key: "@playwright/test", aliases: ["@playwright/test"] },
  { key: "typescript",       aliases: ["typescript"] },
  { key: "lint-staged",      aliases: ["lint-staged"] },
  { key: "eslint",           aliases: ["eslint"] },
  { key: "prettier",         aliases: ["prettier"] },
  { key: "husky",            aliases: ["husky"] },
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


if [[ "${MISSING_COUNT:-0}" == "0" && "${MISSING_PACKAGES_COUNT:-0}" == "0" ]]; then
  SPAN_DECISION="skip"
  SPAN_DETAIL="all-checks-pass"
  exit 0
fi

# ─── Emit additionalContext JSON ────────────────────────────────────────────
OUT=$(node -e '
const missing = JSON.parse(process.argv[1] || "[]");
const missingPkgs = JSON.parse(process.argv[2] || "[]");

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
  "🎭 PLAYWRIGHT SETUP CHECK — phát hiện " + total + " mục bắt buộc chưa có.",
  "",
  "Plugin playwright yêu cầu consumer setup tối thiểu để hooks/skills hoạt động đầy đủ:",
  "",
  sections.join("\n\n"),
  "",
  "═══ Hướng dẫn ═══",
  "  • Cài @playwright/test: npm i -D @playwright/test && npx playwright install",
  "  • Cài typescript:       npm i -D typescript",
  "  • Tạo tsconfig.json (narrow scope) — xem skill playwright-setup § 4:",
  "      include: [\"src/**/*.ts\", \"tests/**/*.ts\", \"playwright.config.ts\"]",
  "      paths:   { \"@src/*\": [\"src/*\"] }",
  "  • Cài husky + init:    npm i -D husky && npx husky init",
  "    → tạo .husky/pre-commit (mặc định chạy `npm test`) — edit để chạy `npx lint-staged`",
  "  • Cài package khác:    npm i -D <pkg>  (hoặc yarn add -D / pnpm add -D / bun add -d)",
  "  • Tạo playwright.config.ts: npx playwright init",
  "  • Tạo tests/ dir với cấu trúc: tests/api/{domain}/ và tests/e2e/{domain}/",
  "  • Sau khi fix xong, restart Claude session để hook re-check",
  "",
  "Capability bị degrade theo từng item missing:",
  "  • package.json                      → không detect được test framework",
  "  • playwright.config.ts              → run-test-mark-fixme.sh không tìm được config",
  "  • tsconfig.json                     → tsc default scope = scan toàn project (sai/chậm)",
  "  • tests/                            → không có nơi chứa test specs",
  "  • @playwright/test                  → Playwright runner không available",
  "  • typescript                        → tsc không chạy được, type-check off",
  "  • .husky/ + .husky/pre-commit       → Git pre-commit hook KHÔNG fire (lint/test bypass)",
  "  • husky package                     → `npm install` không tự install Git hooks",
  "  • lint-staged                       → format-on-commit gate hỏng",
  "  • eslint / prettier                 → code quality enforcement off",
  "",
  "Plugin-specific checks (xem thêm):",
  "  • bmad-workflows   → _bmad/bmm/config.yaml, docs/roadmap/, docs/templates/",
  "  • test-enforcement → src/fixtures/, src/pages/, src/helpers/, src/factories/",
  "  • observability    → LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY",
];


lines.push(
  "",
  "Bypass: SKIP_PLAYWRIGHT_SETUP=1 (per-hook) hoặc SKIP_HOOKS=1 (master).",
  "Tuỳ biến: CONSUMER_REQUIRED_PATHS (newline) thêm path; CONSUMER_SETUP_SKIP_DEFAULTS=1 bỏ defaults."
);

const out = {
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: lines.join("\n")
  }
};
process.stdout.write(JSON.stringify(out));
' "$MISSING_JSON" "$MISSING_PACKAGES_JSON")

printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="missing-paths=$MISSING_COUNT,missing-pkgs=$MISSING_PACKAGES_COUNT"

exit 0
