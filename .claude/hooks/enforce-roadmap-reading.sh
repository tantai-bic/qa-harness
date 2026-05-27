#!/bin/bash
# UserPromptSubmit hook: bắt buộc đọc docs/roadmap/README.md → phase doc → upstream
# đệ quy khi user prompt liên quan campaign feature/phase.
#
# Workflow yêu cầu Claude:
#   1. Tìm tính năng sắp làm trong docs/roadmap/README.md (index)
#   2. Đọc phase doc tương ứng — chú ý § "Upstream"
#   3. ĐỆ QUY: đọc phase upstream → § "Upstream" của nó → đến khi tới Phase A
#
# Trigger keywords (case-insensitive):
#   - Phase: phase a/b/c/d · phaseA/B/C/D
#   - Domain: campaign, validation, tactic, pledge, delivery, refund, escrow,
#             concept, refinement, goal, publish, dashboard, Q1-Q7, dispute,
#             checkout, hero-media, landing-page, withdrawal, traffic light
#   - File path: src/{campaign,validation,goal,delivery,pledge,refund,dispute,
#                     escrow,refinement,poll-tactic,campaign-page,campaign-goal,
#                     creator-dashboard}/
#   - Test path: tests/api/ · tests/e2e/
#   - Vietnamese: tính năng, làm tính năng, implement, viết test, tạo test
#
# Bypass: SKIP_ROADMAP_READING=1  (per-hook)
#         SKIP_HOOKS=1             (master — disables all bypass-aware hooks)
#
# Per CLAUDE.md: dùng `node -e` để parse JSON (jq không có trên Windows Git Bash).

set -uo pipefail

SPAN_HOOK_NAME="enforce-roadmap-reading"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_ROADMAP_READING:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_ROADMAP_READING"
  exit 0
fi

PROMPT=$(node -e '
try {
  const input = JSON.parse(require("fs").readFileSync(0, "utf-8"));
  process.stdout.write(input.prompt || "");
} catch (e) { process.exit(0); }
' <<< "$INPUT" 2>/dev/null)

[[ -z "$PROMPT" ]] && exit 0

LC_PROMPT=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# ─── Phase detection ────────────────────────────────────────────────────────
PHASES=()

if echo "$LC_PROMPT" | grep -qE 'phase[ _-]*a|phasea|\bconcept\b|refinement|q1-q7|q1q7|ai concept|src/refinement'; then
  PHASES+=("A")
fi
if echo "$LC_PROMPT" | grep -qE 'phase[ _-]*b|phaseb|\bvalidation\b|\btactic|poll[ _-]?tactic|email[ _-]?survey|landing[ _-]?page|traffic[ _-]?light|review.*validat|src/validation|src/poll-tactic'; then
  PHASES+=("B")
fi
if echo "$LC_PROMPT" | grep -qE 'phase[ _-]*c|phasec|\bgoal|publish|funding|\bpledge|checkout|\bbacker|live[ _-]?campaign|hero[ _-]?media|q[ _-]?and[ _-]?a|\bq&a\b|src/goal|src/pledge|src/campaign-goal|src/campaign-page|src/checkout|src/campaign-q-and-a'; then
  PHASES+=("C")
fi
if echo "$LC_PROMPT" | grep -qE 'phase[ _-]*d|phased|\bdelivery|\brefund|\bescrow|\bdispute|withdrawal|fund[ _-]?release|verify[ _-]?backer|src/delivery|src/refund|src/dispute|src/escrow|src/withdrawal'; then
  PHASES+=("D")
fi

# Generic campaign signals → suggest all phases (uncertain target)
if [[ ${#PHASES[@]} -eq 0 ]]; then
  if echo "$LC_PROMPT" | grep -qE '\bcampaign\b|src/campaign|creator[ _-]?dashboard|tests/api|tests/e2e|tính năng|làm tính năng|implement|viết test|tạo test|seed.*phase|phase.*seed'; then
    PHASES=("?")
  fi
fi

# No signal → exit silently (SPAN_DECISION stays "skip")
[[ ${#PHASES[@]} -eq 0 ]] && exit 0

# ─── Compute highest-phase target + reading chain ───────────────────────────
HIGHEST=""
for P in "${PHASES[@]}"; do
  case "$P" in
    A) [[ -z "$HIGHEST" ]] && HIGHEST="A" ;;
    B) [[ "$HIGHEST" != "C" && "$HIGHEST" != "D" ]] && HIGHEST="B" ;;
    C) [[ "$HIGHEST" != "D" ]] && HIGHEST="C" ;;
    D) HIGHEST="D" ;;
    "?") [[ -z "$HIGHEST" ]] && HIGHEST="?" ;;
  esac
done

case "$HIGHEST" in
  A) CHAIN="phaseA" ;;
  B) CHAIN="phaseB → phaseA" ;;
  C) CHAIN="phaseC → phaseB → phaseA" ;;
  D) CHAIN="phaseD → phaseC → phaseB → phaseA" ;;
  "?") CHAIN="(chưa xác định) — đọc README rồi chọn phase đúng, sau đó đệ quy upstream" ;;
esac

PHASE_LIST=$(IFS=, ; echo "${PHASES[*]}")

# ─── Emit additionalContext JSON ────────────────────────────────────────────
OUT=$(node -e '
const phases = process.argv[1];
const chain = process.argv[2];
const highest = process.argv[3];
const msg = [
  "📚 ROADMAP READING REQUIRED — phát hiện feature liên quan Phase [" + phases + "]",
  "",
  "Trước khi implement / sửa code / viết test, BẮT BUỘC thực hiện workflow:",
  "",
  "  ① Read  docs/roadmap/README.md  (index — xác nhận feature mapping)",
  "  ② Read  docs/roadmap/campaign/phase" + highest + ".md  (target phase)",
  "          → tập trung § \"Upstream\" — deps để phase hoạt động đúng",
  "          → § \"State\" — trạng thái sau khi vào phase",
  "          → § \"Constraints\" — failure log + BE quirks",
  "          → § \"Service / Factory / Helper layer\" — gọi đúng API (F-1: KHÔNG request.post trực tiếp)",
  "  ③ ĐỆ QUY upstream: với mỗi phase đọc ở bước ②, identify phase upstream từ § \"Upstream\",",
  "          rồi đọc doc upstream đó và lặp lại § \"Upstream\" check.",
  "          Dừng khi tới Phase A (no upstream within campaign lifecycle — chỉ deps auth/UUID).",
  "",
  "Reading chain cho prompt này:  " + chain,
  "",
  "Tại sao recursion: feature ở Phase X chỉ hoạt động đúng nếu upstream X-1, X-2, ... được seed đúng",
  "(vd: Phase B mock chỉ usable khi Phase B status=draft tức cần fresh campaign từ Phase A; Phase C",
  "goal cần Phase B status=completed; Phase D delivery cần Phase C publish + funding success).",
  "",
  "Note: TEST-QUALITY-CHECKLIST.md được enforce riêng bởi orchestrate-test-automation hook khi viết test.",
  "      Hook roadmap này chỉ focus vào phase dependencies.",
  "",
  "Bypass: SKIP_ROADMAP_READING=1 (per-hook) hoặc SKIP_HOOKS=1 (master). Chỉ set khi đã đọc rồi.",
].join("\n");

const out = {
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: msg
  }
};
process.stdout.write(JSON.stringify(out));
' "$PHASE_LIST" "$CHAIN" "$HIGHEST")
printf '%s' "$OUT"
SPAN_DECISION="inject"
SPAN_BYTES=${#OUT}
SPAN_DETAIL="phases=[$PHASE_LIST] chain=$CHAIN"

exit 0
