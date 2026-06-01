#!/bin/bash
# SessionStart hook: check test-enforcement-specific consumer setup.
# Checks: src/fixtures, src/pages, src/components, src/helpers, src/factories,
#         src/constants/api.constants.ts, @playwright/test package
# Bypass: SKIP_SETUP_CHECK=1 | SKIP_HOOKS=1

set -uo pipefail

SPAN_HOOK_NAME="test-enforcement-check-setup"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_SETUP_CHECK:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_SETUP_CHECK"
  exit 0
fi

SOURCE=$(node -e '
try { process.stdout.write(JSON.parse(require("fs").readFileSync(0,"utf-8")).source||""); }
catch { process.exit(0); }
' <<< "$INPUT" 2>/dev/null)
[[ "$SOURCE" != "startup" ]] && { SPAN_DECISION="skip"; SPAN_DETAIL="source=$SOURCE"; exit 0; }

[[ -f ".claude-plugin/marketplace.json" ]] && { SPAN_DECISION="skip"; SPAN_DETAIL="plugin-self"; exit 0; }

# ─── Check required paths ────────────────────────────────────────────────────
MISSING=()
HINTS=()

_check() {
  local label="$1"; local hint="$2"; shift 2
  for p in "$@"; do [[ -e "$p" ]] && return; done
  MISSING+=("$label"); HINTS+=("$hint")
}

_check "src/constants/api.constants.ts" \
  "Khai báo API_ENDPOINTS — hook block nếu spec hardcode URL" \
  "src/constants/api.constants.ts"

_check "src/fixtures" \
  "mkdir src/fixtures — import test từ @src/fixtures (Rule 4a)" \
  "src/fixtures"

_check "src/pages (POM)" \
  "mkdir src/pages — Page Object Model cho E2E tests" \
  "src/pages" "src/page-objects" "tests/pages"

_check "src/components (COM)" \
  "mkdir src/components — Component Object Model (login form, nav, modal)" \
  "src/components" "src/component-objects"

_check "src/helpers" \
  "mkdir src/helpers — parseErrorResponse, *WithoutAuth, response asserts" \
  "src/helpers" "src/utils"

_check "src/factories" \
  "mkdir src/factories — createXPayload() factories, parallel-safe (Rule 3)" \
  "src/factories" "src/data-factories"

# ─── Check @playwright/test package ─────────────────────────────────────────
MISSING_PKG=$(node -e '
const fs = require("fs");
try {
  const p = JSON.parse(fs.readFileSync("package.json","utf-8"));
  const all = {...(p.dependencies||{}), ...(p.devDependencies||{})};
  process.stdout.write((all["playwright"]||all["@playwright/test"]) ? "" : "@playwright/test");
} catch { process.stdout.write(""); }
' 2>/dev/null)
[[ -n "$MISSING_PKG" ]] && { MISSING+=("@playwright/test package"); HINTS+=("npm i -D @playwright/test"); }

[[ ${#MISSING[@]} -eq 0 ]] && { SPAN_DECISION="skip"; SPAN_DETAIL="all-pass"; exit 0; }

# ─── Emit additionalContext ──────────────────────────────────────────────────
ITEMS=""
for i in "${!MISSING[@]}"; do
  ITEMS="${ITEMS}  $((i+1)). \`${MISSING[$i]}\` — ${HINTS[$i]}\n"
done

OUT=$(node -e '
const items = process.argv[1];
const count = parseInt(process.argv[2], 10);
const out = {
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: [
      "🛡️ [test-enforcement] SETUP CHECK — " + count + " mục chưa có:\n",
      items,
      "Capability bị ảnh hưởng:",
      "  • src/constants/api.constants.ts → spec vi phạm Rule: hardcode URL",
      "  • src/fixtures/                  → spec không import từ @src/fixtures (Rule 4a)",
      "  • src/pages, src/components      → enforce-fixture-helper-prerequisite block",
      "  • src/helpers, src/factories     → factory + helper pattern (Rule 3) fail",
      "  • @playwright/test               → run-test-mark-fixme.sh không chạy được",
      "",
      "Bypass: SKIP_SETUP_CHECK=1"
    ].join("\n")
  }
};
process.stdout.write(JSON.stringify(out));
' "$ITEMS" "${#MISSING[@]}")

printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="missing=${#MISSING[@]}"
exit 0
