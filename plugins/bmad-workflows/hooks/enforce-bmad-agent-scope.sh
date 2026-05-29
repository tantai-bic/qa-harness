#!/usr/bin/env bash
# PreToolUse Write|Edit hook: block khi BMAD agent đang active làm việc SAI ROLE.
#
# Vấn đề giải quyết:
#   - User invoke /bmad:bmm:agents:pm → agent đáng lẽ chỉ edit PRD/Epic docs.
#   - Claude/agent break character → edit src/foo.ts → vi phạm separation of concerns.
#   - Tương tự: dev edit PRD, architect implement code, sm edit business logic.
#
# Cơ chế detect agent active:
#   - Scan transcript file (đường dẫn do hook input cung cấp via .transcript_path)
#   - Tìm marker MỚI NHẤT: `/bmad:bmm:agents:<name>` HOẶC `*dismiss`
#   - Nếu marker cuối = `*dismiss` HOẶC không có agent invocation → no active agent → skip
#   - Nếu marker cuối = agent invocation → role = <name>
#   - Chỉ check trong 200 dòng cuối transcript (avoid stale state từ session cũ)
#
# Role → allowed/denied path matrix (chỉnh tại ROLE_RULES bên dưới):
#   dev        : edit src/tests/dev-notes. KHÔNG edit PRD/epic/architecture/product-brief.
#   pm         : edit PRD/epic/stories. KHÔNG edit source code business.
#   sm         : edit stories/epics/sprint docs. KHÔNG edit source code business.
#   architect  : edit architecture/tech-spec docs. KHÔNG implement code.
#   analyst    : edit research/brief docs. KHÔNG edit code.
#   ux-designer: edit ux-design/wireframe docs. KHÔNG edit code.
#   tech-writer: edit docs/*. KHÔNG edit business code.
#   tea        : edit test-design + test code (*.spec.*, *.test.*). KHÔNG edit business src.
#   quick-flow-solo-dev: full access (no restriction).
#
# Bypass: SKIP_BMAD_SCOPE=1 (per-hook) hoặc SKIP_HOOKS=1 (master).

set -uo pipefail

SPAN_HOOK_NAME="enforce-bmad-agent-scope"
SPAN_T0_NS="$(date +%s%N 2>/dev/null || echo 0)"

if [[ "${SKIP_HOOKS:-}" == "1" ]]; then
  SPAN_DECISION="bypass"; SPAN_BYPASS="SKIP_HOOKS"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi
if [[ "${SKIP_BMAD_SCOPE:-}" == "1" ]]; then
  SPAN_DECISION="bypass"; SPAN_BYPASS="SKIP_BMAD_SCOPE"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"

# Extract target file path
FILE_PATH=$(printf '%s' "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/')
FILE_NORM=$(printf '%s' "$FILE_PATH" | tr '\\' '/' 2>/dev/null | sed 's|/\+|/|g')

if [[ -z "$FILE_NORM" ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="no_file_path"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# Extract transcript path
TRANSCRIPT_PATH=$(printf '%s' "$INPUT" | node -e '
let s = ""; process.stdin.on("data", d => s += d); process.stdin.on("end", () => {
  try { const j = JSON.parse(s); process.stdout.write(j.transcript_path || ""); } catch(e) {}
});' 2>/dev/null)

if [[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="no_transcript"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

# Detect active agent — scan LAST 300 lines for most recent agent invocation OR dismiss
# Markers tìm kiếm:
#   - "/bmad:bmm:agents:<name>"      (slash command invocation)
#   - "*dismiss"                      (user typed dismiss)
LAST_MARKER=$(tail -300 "$TRANSCRIPT_PATH" 2>/dev/null \
  | grep -oE '/bmad:bmm:agents:[a-z-]+|\*dismiss' \
  | tail -1)

if [[ -z "$LAST_MARKER" || "$LAST_MARKER" == "*dismiss" ]]; then
  SPAN_DECISION="skip"; SPAN_DETAIL="no_active_agent"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 0
fi

ACTIVE_AGENT=$(echo "$LAST_MARKER" | sed 's|/bmad:bmm:agents:||')

# ─── Role rules ───────────────────────────────────────────────────────────
# Logic: gán VIOLATION=1 + REASON=... khi path vi phạm role.
# Pattern source code business: src/lib/app + .ts/.tsx/.js/.jsx/.py/.go/.rs/.java/.cs
# (loại trừ *.spec.* / *.test.* — đó là test code)

VIOLATION=0
REASON=""

SOURCE_CODE_REGEX='(^|/)(src|lib|app|server|client|backend|frontend)/(.*\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|cs|rb|php))$'
TEST_CODE_REGEX='\.(spec|test)\.(ts|tsx|js|jsx|mjs|py|go)$'
PRD_DOC_REGEX='(^|/)(prd|product-brief|epics?|architecture|tech-spec|ux-design|brief)\.(md|yaml|yml)$|(^|/)(prd|epics?|architecture|product-briefs?|ux-designs?)/'
STORY_DOC_REGEX='(^|/)stor(y|ies)/[^/]+\.(md|yaml|yml)$|(^|/)sprints?/'
TEST_DESIGN_REGEX='(^|/)test-?design/.*\.(md|yaml|yml)$|test-design\.md$'

is_source_code() { [[ "$FILE_NORM" =~ $SOURCE_CODE_REGEX ]] && ! [[ "$FILE_NORM" =~ $TEST_CODE_REGEX ]]; }
is_test_code()   { [[ "$FILE_NORM" =~ $TEST_CODE_REGEX ]]; }
is_prd_doc()     { [[ "$FILE_NORM" =~ $PRD_DOC_REGEX ]]; }
is_story_doc()   { [[ "$FILE_NORM" =~ $STORY_DOC_REGEX ]]; }

case "$ACTIVE_AGENT" in
  dev)
    if is_prd_doc; then
      VIOLATION=1
      REASON="Dev agent KHÔNG được edit PRD/Epic/Architecture/UX-Design docs."
      EXPECTED_AGENT="pm (PRD/Epic) | architect (Architecture) | ux-designer (UX)"
    fi
    ;;
  pm|analyst)
    if is_source_code || is_test_code; then
      VIOLATION=1
      REASON="$ACTIVE_AGENT agent KHÔNG được edit source/test code — chỉ docs (PRD/Epic/Research)."
      EXPECTED_AGENT="dev (source) | tea (test code)"
    fi
    ;;
  sm)
    if is_source_code || is_test_code; then
      VIOLATION=1
      REASON="SM (Scrum Master) KHÔNG edit code — chỉ stories/epics/sprint docs."
      EXPECTED_AGENT="dev (source) | tea (test code)"
    fi
    ;;
  architect)
    if is_source_code || is_test_code; then
      VIOLATION=1
      REASON="Architect KHÔNG implement code — chỉ design docs (architecture, tech-spec)."
      EXPECTED_AGENT="dev (source) | tea (test code)"
    fi
    ;;
  ux-designer)
    if is_source_code || is_test_code; then
      VIOLATION=1
      REASON="UX Designer KHÔNG edit code — chỉ UX docs / wireframes."
      EXPECTED_AGENT="dev (source) | tea (test code)"
    fi
    ;;
  tech-writer)
    if is_source_code || is_test_code; then
      VIOLATION=1
      REASON="Tech Writer KHÔNG edit code — chỉ docs."
      EXPECTED_AGENT="dev (source) | tea (test code)"
    fi
    ;;
  tea)
    # TEA edit test code + test-design. KHÔNG edit business src.
    if is_source_code; then
      VIOLATION=1
      REASON="TEA (Test Engineer Architect) chỉ edit test code (*.spec.*) + test-design docs, KHÔNG edit business source."
      EXPECTED_AGENT="dev (business source)"
    fi
    ;;
  quick-flow-solo-dev)
    # Solo dev — no restriction
    :
    ;;
  *)
    # Unknown agent — không enforce (safety)
    SPAN_DECISION="skip"; SPAN_DETAIL="unknown_agent=$ACTIVE_AGENT"
    source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
    exit 0
    ;;
esac

if [[ $VIOLATION -eq 1 ]]; then
  {
    echo "🚧 BMAD AGENT SCOPE VIOLATION — agent đang làm sai role"
    echo ""
    echo "Active agent: $ACTIVE_AGENT"
    echo "Target file:  $FILE_NORM"
    echo ""
    echo "$REASON"
    echo ""
    echo "═══ Action ═══"
    echo "  1. *dismiss agent $ACTIVE_AGENT hiện tại"
    echo "  2. Invoke đúng role: $EXPECTED_AGENT"
    echo "     vd: /bmad:bmm:agents:dev"
    echo ""
    echo "Nếu task này thực sự cross-role (vd dev cần update tech-spec sau khi implement):"
    echo "  → user xác nhận → set SKIP_BMAD_SCOPE=1 cho call này"
    echo ""
    echo "Role matrix:"
    echo "  dev        → src/ tests/ dev-notes"
    echo "  pm         → PRD/ epic/ stories/"
    echo "  sm         → stories/ epics/ sprint/"
    echo "  architect  → architecture/ tech-spec/"
    echo "  ux-designer→ ux-design/ wireframes/"
    echo "  tea        → test-design/ *.spec.* *.test.*"
    echo "  analyst    → research/ brief/"
    echo "  tech-writer→ docs/ README"
    echo ""
    echo "Bypass: SKIP_BMAD_SCOPE=1 (per-hook) hoặc SKIP_HOOKS=1 (master)."
  } >&2

  SPAN_DECISION="block"
  SPAN_DETAIL="agent=$ACTIVE_AGENT path=$FILE_NORM"
  source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
  exit 2
fi

SPAN_DECISION="pass"
SPAN_DETAIL="agent=$ACTIVE_AGENT"
source "$(dirname "$0")/_hook-span-emit.sh" 2>/dev/null || true
exit 0
