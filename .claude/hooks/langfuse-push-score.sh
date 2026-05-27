#!/bin/bash
# Wrapper tiện dụng để push 1 hoặc nhiều Langfuse score event + flush ngay.
#
# ─── Verify-and-retry guarantee ─────────────────────────────────────────────
# Sau khi push, script QUERY server để xác nhận TẤT CẢ scores đã landed.
# Nếu thiếu → re-push tự động (max LANGFUSE_VERIFY_RETRY=3, sleep 2s mỗi attempt).
# Deterministic scoreId = sha256(traceId + ":" + name) format UUID → retry IDEMPOTENT
# (cùng id → server update value, KHÔNG tạo duplicate).
#
# Chỉ STOP khi:
#   ✓ All scores confirmed (exit 0)
#   ✗ Retry exhausted (exit 1)
#   ⊘ Server error 5xx / connection failed / 4xx auth (exit 0, queue local retry sau)
#
# Bypass verify: LANGFUSE_VERIFY_SCORES=0  (chỉ enqueue + flush, không xác nhận)
# Tune: LANGFUSE_VERIFY_RETRY=3  LANGFUSE_VERIFY_WAIT=2
#
# ─── Mode 1: Single score (1 tiêu chí) ──────────────────────────────────────
#   bash .claude/hooks/langfuse-push-score.sh \
#     --trace-id <traceId>                  (bắt buộc)
#     --name <criterion>                    (bắt buộc — vd "user-satisfaction")
#     --value <num|true|false|string>       (bắt buộc — auto-detect dataType)
#     [--comment "<text>"]                  (optional)
#     [--session-id <sessionId>]            (optional — default: trùng traceId)
#     [--data-type NUMERIC|BOOLEAN|CATEGORICAL]  (optional — override auto-detect)
#     [--observation-id <id>]               (optional — score 1 observation cụ thể)
#
# ─── Mode 2: Matrix template (batch push nhiều tiêu chí 1 lần) ──────────────
#   bash .claude/hooks/langfuse-push-score.sh \
#     --trace-id <traceId> \
#     --template <name>          (test-quality | code-review | custom)
#     [--session-id <sessionId>]
#   << EOF
#   {
#     "convention-adherence": [1.0, "Comment cho criterion 1"],
#     "test-isolation":       [0.9, "Comment cho criterion 2"],
#     ...
#   }
#   EOF
#
#   → push 1 score event cho mỗi key, dataType auto-detect.
#   → Nếu --template cụ thể: validate keys match template criteria, warn missing/extra.
#   → Nếu --template custom: chấp nhận bất kỳ key nào.
#
# ─── Mode 3: List templates ─────────────────────────────────────────────────
#   bash .claude/hooks/langfuse-push-score.sh --list-templates
#
# Env required: LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY
# Sau khi push, flush ngay (POST tới Langfuse). Nếu offline → giữ queue retry.

set -uo pipefail

# ─── Score Matrix Templates ─────────────────────────────────────────────────
# Format: "criterion-name|description" (1 line per criterion)
declare -A TEMPLATES

TEMPLATES[test-quality]="convention-adherence|Tuân thủ project rule (fixture, path alias, file split P0/P1/P2)
test-isolation|Tests độc lập, auto-cleanup, không shared state
coverage-breadth|Phủ edge cases: BVA, equivalence class, security, error scenarios
error-parsing-depth|Validate error body shape (parseErrorResponse, getFieldErrorMessage)
maintainability|LOC reasonable, header doc, lean test body, fixture-driven
eslint-first-pass|Code sạch TS/ESLint ngay từ đầu, không phải fix sau
overall-quality|Composite score — production-readiness toàn cục"

TEMPLATES[code-review]="correctness|Logic đúng, không bug rõ ràng
security|Không leak secrets, không injection, auth/authz check
performance|Không N+1 query, không blocking call, complexity hợp lý
maintainability|Readable, đặt tên tốt, comment đúng chỗ
test-coverage|Có test cho code mới, test cover edge cases
backward-compat|Không break existing API/contract
overall-quality|Composite score — sẵn sàng merge hay không"

# Template observability — 3-axis score: Accuracy × Token efficiency × Cost (USD)
# Filter rule: nếu accuracy_score=0.0 → ép token + cost = 0.0 (lãng phí tuyệt đối).
# Linear penalty thresholds (override qua env LANGFUSE_TOKEN_TARGET / TOKEN_MAX / COST_TARGET / COST_MAX):
#   TOKEN_TARGET=200000  TOKEN_MAX=2000000   (multi-turn code-writing với cache reads)
#   COST_TARGET=0.10     COST_MAX=1.00
TEMPLATES[accuracy-efficiency]="accuracy_score|Pass/Warning/Fail (1.0/0.5/0.0): error_retry > 1 → 0.5. Hook quality gate KHÔNG bị phạt
token_efficiency_score|Linear penalty từ TOKEN_TARGET(200K) → TOKEN_MAX(2M). cache_read trừ × 0.1 (cheap)
cost_score|Linear penalty từ COST_TARGET($0.10) → COST_MAX($1.00). Phạt model selection sai (Opus cho task dễ)
value_score|Composite (5·quality + 3·accuracy + 1·cost_eff + 1·token_eff)/10. Quality-weighted để fit production trade-off"

# ─── Parse args ─────────────────────────────────────────────────────────────
TRACE_ID=""
NAME=""
VALUE=""
COMMENT=""
SESSION_ID=""
DATA_TYPE=""
OBSERVATION_ID=""
TEMPLATE=""
LIST_TEMPLATES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace-id)        TRACE_ID="$2"; shift 2 ;;
    --name)            NAME="$2"; shift 2 ;;
    --value)           VALUE="$2"; shift 2 ;;
    --comment)         COMMENT="$2"; shift 2 ;;
    --session-id)      SESSION_ID="$2"; shift 2 ;;
    --data-type)       DATA_TYPE="$2"; shift 2 ;;
    --observation-id)  OBSERVATION_ID="$2"; shift 2 ;;
    --template)        TEMPLATE="$2"; shift 2 ;;
    --list-templates)  LIST_TEMPLATES=1; shift ;;
    -h|--help)
      sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

# ─── Mode 3: List templates ─────────────────────────────────────────────────
if [[ -n "$LIST_TEMPLATES" ]]; then
  echo "📋 Available Score Matrix templates:"
  echo ""
  for tname in "${!TEMPLATES[@]}"; do
    echo "═══ --template $tname ═══"
    while IFS='|' read -r crit desc; do
      printf "  %-22s %s\n" "$crit" "$desc"
    done <<< "${TEMPLATES[$tname]}"
    echo ""
  done
  echo "Usage:"
  echo "  bash $0 --trace-id <id> --template test-quality << 'EOF'"
  echo "  { \"convention-adherence\": [1.0, \"Comment\"], ... }"
  echo "  EOF"
  exit 0
fi

# ─── Push single score helper (shared by both modes) ────────────────────────
# Deterministic scoreId = sha256(traceId + ":" + name) format UUID → retries idempotent
# (POST cùng scoreId → server update value thay vì tạo duplicate)
push_one() {
  local _trace_id="$1" _name="$2" _value="$3" _comment="$4"
  local _session_id="$5" _data_type="$6" _observation_id="$7"

  node -e '
const crypto = require("crypto");
const trace = process.argv[1];
const name = process.argv[2];
const h = crypto.createHash("sha256").update(trace + ":" + name).digest("hex");
const scoreId = h.slice(0,8) + "-" + h.slice(8,12) + "-4" + h.slice(13,16) + "-" + h.slice(16,20) + "-" + h.slice(20,32);
process.stdout.write(JSON.stringify({
  scoreId,
  traceId: trace,
  name,
  value: (() => {
    const v = process.argv[3];
    if (/^-?\d+(\.\d+)?$/.test(v)) return Number(v);
    if (v === "true") return true;
    if (v === "false") return false;
    return v;
  })(),
  comment: process.argv[4] || undefined,
  dataType: process.argv[5] || undefined,
  observationId: process.argv[6] || undefined,
}));
' "$_trace_id" "$_name" "$_value" "$_comment" "$_data_type" "$_observation_id" \
    | node .claude/hooks/langfuse-helper.js score "$_session_id"

  return $?
}

# ─── Verify scores landed on server + retry missing ────────────────────────
# Returns 0 if all confirmed, 1 if retries exhausted, 2 if server error (5xx/timeout)
verify_scores_on_server() {
  local _trace_id="$1" _session_id="$2"
  shift 2
  local _expected_names=("$@")
  local _max_retry="${LANGFUSE_VERIFY_RETRY:-3}"
  local _wait_seconds="${LANGFUSE_VERIFY_WAIT:-2}"

  if [[ -z "${LANGFUSE_PUBLIC_KEY:-}" || -z "${LANGFUSE_SECRET_KEY:-}" ]]; then
    echo "  ⚠ Langfuse chưa configured — skip verify (events queued local)"
    return 0
  fi

  for attempt in $(seq 1 "$_max_retry"); do
    sleep "$_wait_seconds"

    # HEAD-style probe: check HTTP status first
    local _http_code
    _http_code=$(curl -s -o /dev/null -w "%{http_code}" \
      -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" \
      "$LANGFUSE_HOST/api/public/traces/$_trace_id" 2>/dev/null)

    if [[ -z "$_http_code" || "$_http_code" == "000" ]]; then
      echo "  ⚠ Server unreachable (connection failed) — STOP verify"
      return 2
    fi
    if [[ "$_http_code" =~ ^5 ]]; then
      echo "  ⚠ Server error HTTP $_http_code — STOP verify"
      return 2
    fi
    if [[ "$_http_code" == "404" ]]; then
      echo "  ⚠ Trace $_trace_id chưa tồn tại trên server (404) — chờ ingestion..."
      continue
    fi

    # Fetch + parse score names on server
    local _server_names
    _server_names=$(curl -s -u "$LANGFUSE_PUBLIC_KEY:$LANGFUSE_SECRET_KEY" \
      "$LANGFUSE_HOST/api/public/traces/$_trace_id" 2>/dev/null | node -e '
try {
  const d = JSON.parse(require("fs").readFileSync(0, "utf-8"));
  const names = [...new Set((d.scores || []).map(s => s.name))];
  process.stdout.write(names.join("\n"));
} catch (e) { process.exit(1); }
')

    # Find missing
    local _missing=()
    for n in "${_expected_names[@]}"; do
      if ! echo "$_server_names" | grep -qFx "$n"; then
        _missing+=("$n")
      fi
    done

    if [[ ${#_missing[@]} -eq 0 ]]; then
      echo "  ✓ Verified ${#_expected_names[@]} scores trên server (attempt $attempt)"
      return 0
    fi

    echo "  ⚠ Attempt $attempt/$_max_retry: ${#_missing[@]} missing on server → re-push: ${_missing[*]}"

    # Re-push missing
    for n in "${_missing[@]}"; do
      local _key="${_trace_id}__${n}"
      local _v="${SCORE_VALUE[$_key]:-}"
      local _c="${SCORE_COMMENT[$_key]:-}"
      if [[ -z "$_v" ]]; then
        echo "    ✗ Cannot retry $n — value not cached"
        continue
      fi
      push_one "$_trace_id" "$n" "$_v" "$_c" "$_session_id" "" "" > /dev/null
    done
  done

  echo "  ✗ After $_max_retry attempts, vẫn missing trên server: ${_missing[*]}"
  return 1
}

report_one() {
  local _rc="$1" _trace_id="$2" _name="$3" _value="$4" _session_id="$5"
  local _safe_session
  _safe_session=$(node -e 'process.stdout.write(String(process.argv[1]||"").replace(/[^a-zA-Z0-9_-]/g, "_").slice(0,64) || "unknown")' "$_session_id")
  local _qfile=".claude/hooks/.langfuse-queue/${_safe_session}.jsonl"

  if [[ $_rc -ne 0 ]]; then
    echo "  ✗ score push failed (exit $_rc) — name=$_name" >&2
    return $_rc
  fi
  if [[ -z "${LANGFUSE_PUBLIC_KEY:-}" || -z "${LANGFUSE_SECRET_KEY:-}" ]]; then
    echo "  ⚠ Langfuse CHƯA configured — score $_name queued LOCAL ($_qfile)"
  elif [[ -f "$_qfile" ]]; then
    echo "  ⚠ score $_name enqueued NHƯNG POST failed (retry next flush)"
  else
    echo "  ✓ $_name = $_value"
  fi
  return 0
}

# ─── Mode 2: Matrix template (batch) ────────────────────────────────────────
if [[ -n "$TEMPLATE" ]]; then
  if [[ -z "$TRACE_ID" ]]; then
    echo "Error: --trace-id bắt buộc trong matrix mode." >&2
    exit 2
  fi
  SESSION_ID="${SESSION_ID:-$TRACE_ID}"

  # Validate template name (allow "custom" = no validation)
  if [[ "$TEMPLATE" != "custom" && -z "${TEMPLATES[$TEMPLATE]:-}" ]]; then
    echo "Error: template '$TEMPLATE' không tồn tại." >&2
    echo "Run: bash $0 --list-templates" >&2
    exit 2
  fi

  # Read JSON from stdin
  STDIN_JSON=$(cat)
  if [[ -z "$STDIN_JSON" ]]; then
    echo "Error: Matrix mode cần JSON input qua stdin (heredoc hoặc pipe)." >&2
    echo "  Vd: bash $0 --trace-id X --template test-quality <<EOF" >&2
    echo "      { \"convention-adherence\": [1.0, \"Comment\"], ... }" >&2
    echo "      EOF" >&2
    exit 2
  fi

  # Parse JSON + validate against template
  PARSED=$(node -e '
const tplCriteria = process.argv[1] ? process.argv[1].split("\n").map(l => l.split("|")[0]) : null;
let data;
try { data = JSON.parse(require("fs").readFileSync(0, "utf-8")); }
catch (e) { console.error("✗ Invalid JSON: " + e.message); process.exit(3); }
if (typeof data !== "object" || Array.isArray(data) || data === null) {
  console.error("✗ Input must be JSON object: { \"criterion-name\": [value, \"comment\"], ... }");
  process.exit(3);
}
const entries = Object.entries(data);
if (entries.length === 0) { console.error("✗ Empty matrix"); process.exit(3); }

// Validate against template
if (tplCriteria) {
  const inputKeys = new Set(entries.map(([k]) => k));
  const missing = tplCriteria.filter(c => !inputKeys.has(c));
  const extra = [...inputKeys].filter(k => !tplCriteria.includes(k));
  if (missing.length) console.error("⚠ Missing criteria: " + missing.join(", "));
  if (extra.length)   console.error("⚠ Extra criteria (not in template): " + extra.join(", "));
}

// Output TSV: name\tvalue\tcomment
for (const [name, payload] of entries) {
  let value, comment = "";
  if (Array.isArray(payload)) { value = payload[0]; comment = payload[1] || ""; }
  else if (typeof payload === "object" && payload !== null) { value = payload.value; comment = payload.comment || ""; }
  else { value = payload; }
  if (value === undefined || value === null) {
    console.error(`⚠ Skip ${name}: missing value`);
    continue;
  }
  process.stdout.write(`${name}\t${value}\t${comment.replace(/\t/g, " ").replace(/\n/g, " ")}\n`);
}
' "${TEMPLATES[$TEMPLATE]:-}" <<< "$STDIN_JSON")

  PARSE_RC=$?
  if [[ $PARSE_RC -ne 0 ]]; then exit $PARSE_RC; fi
  if [[ -z "$PARSED" ]]; then
    echo "✗ No valid scores to push." >&2
    exit 3
  fi

  echo "📊 Matrix push — template=$TEMPLATE trace=$TRACE_ID"

  # Cache values + comments cho retry (assoc arrays scoped to matrix mode)
  declare -A SCORE_VALUE
  declare -A SCORE_COMMENT
  EXPECTED_NAMES=()

  TOTAL=0
  OK=0
  while IFS=$'\t' read -r _name _value _comment; do
    [[ -z "$_name" ]] && continue
    TOTAL=$((TOTAL + 1))
    EXPECTED_NAMES+=("$_name")
    SCORE_VALUE["${TRACE_ID}__${_name}"]="$_value"
    SCORE_COMMENT["${TRACE_ID}__${_name}"]="$_comment"

    push_one "$TRACE_ID" "$_name" "$_value" "$_comment" "$SESSION_ID" "" ""
    RC=$?
    if report_one "$RC" "$TRACE_ID" "$_name" "$_value" "$SESSION_ID"; then
      OK=$((OK + 1))
    fi
  done <<< "$PARSED"

  echo ""
  echo "Done: $OK/$TOTAL scores enqueued for trace $TRACE_ID"

  # ─── Verify all scores landed on Langfuse server (with retry) ─────────────
  # Bypass: LANGFUSE_VERIFY_SCORES=0 → skip verification (chỉ enqueue + flush)
  if [[ "${LANGFUSE_VERIFY_SCORES:-1}" == "1" ]]; then
    echo ""
    echo "🔍 Verifying scores on Langfuse server..."
    verify_scores_on_server "$TRACE_ID" "$SESSION_ID" "${EXPECTED_NAMES[@]}"
    VERIFY_RC=$?
    case $VERIFY_RC in
      0) echo "✓ All ${#EXPECTED_NAMES[@]} scores confirmed on server."; exit 0 ;;
      1) echo "✗ Some scores STILL missing sau retry — check Langfuse UI" >&2; exit 1 ;;
      2) echo "⊘ Stopped do server error — scores có thể đã enqueue local, sẽ retry lần flush sau" >&2; exit 0 ;;
    esac
  fi
  exit 0
fi

# ─── Mode 1: Single score (legacy interface) ────────────────────────────────
if [[ -z "$TRACE_ID" || -z "$NAME" || -z "$VALUE" ]]; then
  echo "Error: --trace-id, --name, --value đều bắt buộc (single mode)." >&2
  echo "       Hoặc dùng --template <name> với stdin JSON (matrix mode)." >&2
  echo "Run: bash $0 --help  |  bash $0 --list-templates" >&2
  exit 2
fi

SESSION_ID="${SESSION_ID:-$TRACE_ID}"

push_one "$TRACE_ID" "$NAME" "$VALUE" "$COMMENT" "$SESSION_ID" "$DATA_TYPE" "$OBSERVATION_ID"
RC=$?

SAFE_SESSION=$(node -e 'process.stdout.write(String(process.argv[1]||"").replace(/[^a-zA-Z0-9_-]/g, "_").slice(0,64) || "unknown")' "$SESSION_ID")
QUEUE_FILE=".claude/hooks/.langfuse-queue/${SAFE_SESSION}.jsonl"

if [[ $RC -ne 0 ]]; then
  echo "✗ score push failed (exit $RC)" >&2
  exit $RC
fi

if [[ -z "${LANGFUSE_PUBLIC_KEY:-}" || -z "${LANGFUSE_SECRET_KEY:-}" ]]; then
  echo "⚠ Langfuse CHƯA configured — score đã queue LOCAL, KHÔNG push được."
  echo "   queue file:  $QUEUE_FILE"
  echo "   trace_id:    $TRACE_ID"
  echo "   name=$NAME  value=$VALUE"
  echo ""
  echo "   Để push: set LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY, rồi run:"
  echo "     node .claude/hooks/langfuse-helper.js flush \"$SESSION_ID\""
  exit 0
elif [[ -f "$QUEUE_FILE" ]]; then
  echo "⚠ score đã enqueue NHƯNG POST tới Langfuse failed (queue file vẫn còn) → retry next flush."
  echo "   queue: $QUEUE_FILE"
  echo "   trace_id=$TRACE_ID  name=$NAME  value=$VALUE"
else
  echo "✓ score enqueued + flushed locally"
  echo "   trace_id=$TRACE_ID  name=$NAME  value=$VALUE"
fi

# Single-mode verify: cache value cho retry function rồi gọi verify_scores_on_server
if [[ "${LANGFUSE_VERIFY_SCORES:-1}" == "1" && -n "${LANGFUSE_PUBLIC_KEY:-}" ]]; then
  declare -A SCORE_VALUE
  declare -A SCORE_COMMENT
  SCORE_VALUE["${TRACE_ID}__${NAME}"]="$VALUE"
  SCORE_COMMENT["${TRACE_ID}__${NAME}"]="$COMMENT"
  echo ""
  echo "🔍 Verifying score on Langfuse server..."
  verify_scores_on_server "$TRACE_ID" "$SESSION_ID" "$NAME"
  VERIFY_RC=$?
  case $VERIFY_RC in
    0) exit 0 ;;
    1) echo "✗ Score still missing sau retry — check Langfuse UI" >&2; exit 1 ;;
    2) echo "⊘ Server error — score đã queued/archived local" >&2; exit 0 ;;
  esac
fi
exit 0
