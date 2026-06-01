#!/bin/bash
# SessionStart hook: check BMAD-specific consumer setup.
# Checks: _bmad/bmm/config.yaml, docs/roadmap/, docs/templates/log-bug-api-template.md
# Bypass: SKIP_SETUP_CHECK=1 | SKIP_HOOKS=1

set -uo pipefail

SPAN_HOOK_NAME="bmad-workflows-check-setup"
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

# Self-skip when running on plugin source repo
if [[ -f ".claude-plugin/marketplace.json" ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="plugin-self"; exit 0
fi

# ─── Check required paths ────────────────────────────────────────────────────
MISSING=()
HINTS=()

_check() {
  local label="$1"; local hint="$2"; shift 2
  for p in "$@"; do
    [[ -e "$p" ]] && return
  done
  MISSING+=("$label"); HINTS+=("$hint")
}

_check "_bmad/bmm/config.yaml" \
  "Tạo file với: project_name, user_name, communication_language, output_folder" \
  "_bmad/bmm/config.yaml"

_check "docs/roadmap/README.md" \
  "Tạo docs/roadmap/README.md — cần cho enforce-roadmap-reading hook" \
  "docs/roadmap/README.md"

_check "docs/templates/log-bug-api-template.md" \
  "Tạo từ template: plugins/bmad-workflows/docs/templates/log-bug-api-template.md" \
  "docs/templates/log-bug-api-template.md"

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
      "🧠 [bmad-workflows] SETUP CHECK — " + count + " mục chưa có:\n",
      items,
      "Capability bị ảnh hưởng:",
      "  • _bmad/bmm/config.yaml       → BMAD agents không activation được",
      "  • docs/roadmap/               → enforce-roadmap-reading hook silent",
      "  • docs/templates/             → thiếu bug log template (hierarchy of truth)",
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
