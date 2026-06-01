#!/bin/bash
# Compute + push 4-axis observability score cho 1 trace.
#
#   axes = { accuracy, token_efficiency, cost, value }
#
# Smart features:
#   • Auto-detect accuracy: phân biệt hook_retry (không phạt) vs error_retry (phạt 0.5)
#   • Cache-weighted token: cache_read tokens × 0.1 (10× cheaper, không inflate efficiency)
#   • Composite value_score: weighted (5·quality + 3·accuracy + 1·cost_eff + 1·token_eff)/10
#
# Usage:
#   bash .claude/hooks/langfuse-score-accuracy-efficiency.sh \
#     --trace-id <traceId>
#     [--accuracy <1.0|0.5|0.0>]      # nếu thiếu → auto-detect từ trace
#     [--accuracy-note "comment"]
#     [--quality <0..1>]              # overall-quality từ test-quality matrix (cho value_score)
#     [--token-target 200000]  [--token-max 2000000]
#     [--cost-target 0.10]     [--cost-max 1.00]
#     [--quality-weight 5]     [--accuracy-weight 3]
#     [--cost-weight 1]        [--token-weight 1]
#
# Env required: LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY + LANGFUSE_HOST

set -uo pipefail

TRACE_ID=""
ACCURACY_OVERRIDE=""
ACC_NOTE=""
QUALITY=""
TOKEN_TARGET="${LANGFUSE_TOKEN_TARGET:-200000}"
TOKEN_MAX="${LANGFUSE_TOKEN_MAX:-2000000}"
COST_TARGET="${LANGFUSE_COST_TARGET:-0.10}"
COST_MAX="${LANGFUSE_COST_MAX:-1.00}"
W_QUALITY="${LANGFUSE_W_QUALITY:-5}"
W_ACCURACY="${LANGFUSE_W_ACCURACY:-3}"
W_COST="${LANGFUSE_W_COST:-1}"
W_TOKEN="${LANGFUSE_W_TOKEN:-1}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace-id)        TRACE_ID="$2"; shift 2 ;;
    --accuracy)        ACCURACY_OVERRIDE="$2"; shift 2 ;;
    --accuracy-note)   ACC_NOTE="$2"; shift 2 ;;
    --quality)         QUALITY="$2"; shift 2 ;;
    --token-target)    TOKEN_TARGET="$2"; shift 2 ;;
    --token-max)       TOKEN_MAX="$2"; shift 2 ;;
    --cost-target)     COST_TARGET="$2"; shift 2 ;;
    --cost-max)        COST_MAX="$2"; shift 2 ;;
    --quality-weight)  W_QUALITY="$2"; shift 2 ;;
    --accuracy-weight) W_ACCURACY="$2"; shift 2 ;;
    --cost-weight)     W_COST="$2"; shift 2 ;;
    --token-weight)    W_TOKEN="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$TRACE_ID" ]]; then
  echo "Error: --trace-id bắt buộc" >&2
  exit 2
fi

# Try fetch overall-quality from existing scores if not provided
if [[ -z "$QUALITY" ]]; then
  QUALITY=$(curl -s -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" \
    "$LANGFUSE_HOST/api/public/traces/$TRACE_ID" | node -e '
const d = JSON.parse(require("fs").readFileSync(0, "utf-8"));
const s = (d.scores || []).find(s => s.name === "overall-quality");
if (s && typeof s.value === "number") process.stdout.write(String(s.value));
')
fi
QUALITY="${QUALITY:-0.5}"  # neutral fallback nếu chưa có

# Fetch trace + compute everything
RESULT=$(curl -s -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" \
  "$LANGFUSE_HOST/api/public/traces/$TRACE_ID" | node -e '
const data = JSON.parse(require("fs").readFileSync(0, "utf-8"));
const obs = data.observations || [];

// ─── Token breakdown (cache-weighted) ─────────────────────────────────────
// effective_tokens = fresh_input + output + cache_creation + cache_read × 0.1
//   Lý do: cache_read là 10× cheaper, không nên đếm full vào token-efficiency penalty.
let rawTokens = 0, freshInput = 0, output = 0, cacheRead = 0, cacheCreate = 0;
let totalCost = 0;

for (const o of obs) {
  if (o.type !== "GENERATION") continue;
  rawTokens += Number(o.totalTokens || 0);
  totalCost += Number(o.calculatedTotalCost || 0);

  // Try detailed breakdown từ metadata._usageDetails (v3 schema preserved)
  const ud = o.metadata && o.metadata._usageDetails;
  if (ud) {
    freshInput  += Number(ud.input || 0);
    output      += Number(ud.output || 0);
    cacheRead   += Number(ud.cache_read_input_tokens || 0);
    cacheCreate += Number(ud.cache_creation_input_tokens || 0);
  } else {
    // Fallback: treat all promptTokens as fresh input
    freshInput += Number(o.promptTokens || 0);
    output     += Number(o.completionTokens || 0);
  }
}

const effectiveTokens = freshInput + output + cacheCreate + Math.round(cacheRead * 0.1);

// ─── Auto-detect accuracy ──────────────────────────────────────────────────
// Scan spans + generation outputs for hook block / error patterns
let hookRetries = 0, errorRetries = 0;
const HOOK_MARKERS = [
  /TEST QUALITY GATE/i,
  /permissionDecision.*deny/i,
  /BLOCK Write/i,
  /Hook y[êe]u c[âa]u/i,
  /Layer [1-9].*MISSING/i,
];
const ERROR_MARKERS = [
  /Error: ENOENT/i,
  /SyntaxError/i,
  /TypeError(?! is not)/i,
  /Test failed/i,
  /TypeScript error/i,
];

for (const o of obs) {
  const text = JSON.stringify({
    input: o.input || "",
    output: o.output || "",
    statusMessage: o.statusMessage || "",
  });
  if (HOOK_MARKERS.some(re => re.test(text))) hookRetries++;
  if (ERROR_MARKERS.some(re => re.test(text))) errorRetries++;
}

let accuracyAuto = 1.0;
if (errorRetries >= 2) accuracyAuto = 0.5;
if (errorRetries >= 5 || obs.length === 0) accuracyAuto = 0.0;

// ─── Read CLI args ─────────────────────────────────────────────────────────
const tokTarget  = parseFloat(process.argv[1]);
const tokMax     = parseFloat(process.argv[2]);
const costTarget = parseFloat(process.argv[3]);
const costMax    = parseFloat(process.argv[4]);
const accOverride = process.argv[5] ? parseFloat(process.argv[5]) : null;
const quality    = parseFloat(process.argv[6]);
const wQ = parseFloat(process.argv[7]);
const wA = parseFloat(process.argv[8]);
const wC = parseFloat(process.argv[9]);
const wT = parseFloat(process.argv[10]);

const accuracy = accOverride !== null && !Number.isNaN(accOverride) ? accOverride : accuracyAuto;

function linearPenalty(actual, target, max) {
  if (actual <= target) return 1.0;
  if (actual >= max)    return 0.0;
  return Math.max(0, Math.min(1, 1.0 - (actual - target) / (max - target)));
}

let tokenScore = linearPenalty(effectiveTokens, tokTarget, tokMax);
let costScore  = linearPenalty(totalCost, costTarget, costMax);

// FILTER RULE: accuracy=0 → ép tất cả = 0
if (accuracy === 0) { tokenScore = 0; costScore = 0; }

// ─── Composite value_score (weighted average) ──────────────────────────────
// value = (W_q × quality + W_a × accuracy + W_c × cost_eff + W_t × token_eff) / totalW
const totalW = wQ + wA + wC + wT;
const valueScore = (wQ * quality + wA * accuracy + wC * costScore + wT * tokenScore) / totalW;

const round = (n) => Math.round(n * 1000) / 1000;
console.log(JSON.stringify({
  rawTokens, effectiveTokens, totalCost,
  freshInput, output, cacheRead, cacheCreate,
  hookRetries, errorRetries,
  accuracyAuto: round(accuracyAuto),
  accuracy: round(accuracy),
  tokenScore: round(tokenScore),
  costScore: round(costScore),
  quality: round(quality),
  valueScore: round(valueScore),
  generations: obs.filter(o => o.type === "GENERATION").length,
}));
' "$TOKEN_TARGET" "$TOKEN_MAX" "$COST_TARGET" "$COST_MAX" "$ACCURACY_OVERRIDE" "$QUALITY" "$W_QUALITY" "$W_ACCURACY" "$W_COST" "$W_TOKEN")

if [[ -z "$RESULT" ]]; then
  echo "✗ Failed to fetch trace $TRACE_ID" >&2
  exit 3
fi

# Extract values
extract() {
  echo "$RESULT" | node -e "const d=JSON.parse(require('fs').readFileSync(0,'utf-8')); console.log(d.$1);"
}

GENS=$(extract generations)
RAW_TOK=$(extract rawTokens)
EFF_TOK=$(extract effectiveTokens)
CACHE_READ=$(extract cacheRead)
COST=$(extract totalCost)
HOOK_R=$(extract hookRetries)
ERR_R=$(extract errorRetries)
ACC_AUTO=$(extract accuracyAuto)
ACC=$(extract accuracy)
TOK_SCORE=$(extract tokenScore)
COST_SCORE=$(extract costScore)
Q=$(extract quality)
VALUE=$(extract valueScore)

echo "📊 Trace $TRACE_ID"
echo "   gens=$GENS  raw_tokens=$RAW_TOK  effective=$EFF_TOK  (cache_read=$CACHE_READ × 0.1)"
echo "   cost=\$$COST  quality=$Q"
echo "   hook_retries=$HOOK_R  error_retries=$ERR_R  →  accuracy_auto=$ACC_AUTO  (final=$ACC)"
echo "   scores: accuracy=$ACC  token=$TOK_SCORE  cost=$COST_SCORE  value=$VALUE"

# Build comments
ACC_NOTE_FINAL="${ACC_NOTE:-Auto: hook_retries=$HOOK_R (KHÔNG phạt), error_retries=$ERR_R. quality_gate retries không phải lỗi}"
TOK_COMMENT="Effective=$EFF_TOK tokens (raw=$RAW_TOK, cache_read×0.1 weighted). Target=$TOKEN_TARGET, Max=$TOKEN_MAX"
COST_COMMENT="Total \$$COST USD. Target=\$$COST_TARGET, Max=\$$COST_MAX"
VALUE_COMMENT="Composite ($W_QUALITY·quality + $W_ACCURACY·accuracy + $W_COST·cost_eff + $W_TOKEN·token_eff)/$((W_QUALITY+W_ACCURACY+W_COST+W_TOKEN)). quality=$Q"

if [[ "$ACC" == "0" ]]; then
  TOK_COMMENT="$TOK_COMMENT. FILTER: accuracy=0 → ép 0"
  COST_COMMENT="$COST_COMMENT. FILTER: accuracy=0 → ép 0"
fi

# Push via matrix
bash "$(dirname "$0")/langfuse-push-score.sh" \
  --trace-id "$TRACE_ID" \
  --template accuracy-efficiency <<EOF
{
  "accuracy_score":         [$ACC,       "$ACC_NOTE_FINAL"],
  "token_efficiency_score": [$TOK_SCORE, "$TOK_COMMENT"],
  "cost_score":             [$COST_SCORE, "$COST_COMMENT"],
  "value_score":            [$VALUE,     "$VALUE_COMMENT"]
}
EOF
