#!/bin/bash
# PreToolUse hook: BLOCK Read duplicate trong cùng session.
#
# Vấn đề: re-read cùng file khi đã có trong context → waste cache_read tokens.
# Typical waste: 0.10–0.30 USD per duplicate, dễ leak vài USD/session khi LLM
# quên file đã đọc và re-Read.
#
# Logic (v2 — compact-aware + edit-error escape):
#   1. Trigger: tool_name=Read + file_path
#   2. Scan transcript JSONL từ LAST compact summary marker (`isCompactSummary:true`)
#      → reset counter sau compact (vì Edit tool nội bộ reset Read state khi compact;
#        Read pre-compact không còn hợp lệ với Edit tool post-compact)
#   3. Track per-target: priorReads / lastAction (read|edit) / editNeedsReread flag
#   4. Detect tool_result is_error chứa "File has not been read" / "must use Read"
#      → set editNeedsReread=true → allow Read (catch-22 escape)
#   5. Có Edit/Write giữa các Read → ALLOW (file đã đổi)
#   6. Edge: nếu Read CŨ + KHÔNG có Edit/Write/error → BLOCK
#
# Path normalization: lowercase + slash unification (Windows + Unix safe)
#
# Bypass: SKIP_READ_DEDUP=1 (per-hook) hoặc SKIP_HOOKS=1 (master)

set -uo pipefail

SPAN_HOOK_NAME="enforce-read-dedup"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_READ_DEDUP:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_READ_DEDUP"
  exit 0
fi

OUT=$(node -e '
const fs = require("fs");
let data;
try { data = JSON.parse(fs.readFileSync(0, "utf-8")); } catch (e) { process.exit(0); }

const toolName = data.tool_name || "";
if (toolName !== "Read") process.exit(0);

const filePath = (data.tool_input && data.tool_input.file_path) || "";
if (!filePath) process.exit(0);

const transcriptPath = data.transcript_path || "";
if (!transcriptPath || !fs.existsSync(transcriptPath)) process.exit(0);

const normalize = (p) => String(p).toLowerCase().replace(/\\/g, "/").replace(/\/+/g, "/");
const target = normalize(filePath);

let transcript;
try { transcript = fs.readFileSync(transcriptPath, "utf-8"); }
catch (e) { process.exit(0); }
const lines = transcript.split("\n").filter(Boolean);

// ─── Find LAST compact marker → reset cutoff ─────────────────────────────
let cutoffIdx = -1;
for (let i = 0; i < lines.length; i++) {
  try {
    const e = JSON.parse(lines[i]);
    if (e.isCompactSummary === true) cutoffIdx = i;
  } catch {}
}

// ─── Walk post-cutoff: track Read/Edit + tool errors ─────────────────────
const EDIT_TOOLS = new Set(["Edit", "Write", "MultiEdit", "NotebookEdit"]);
const READ_NEEDED_RE = /file has not been read|must.*read.*first|read.*before.*(writ|edit)/i;

let priorReads = 0;
let lastActionOnTarget = null;   // "read" | "edit" | null
let editNeedsReread = false;     // Edit/Write failed on target requesting Read
const idMeta = {};               // tool_use_id → { name, path }

for (let i = cutoffIdx + 1; i < lines.length; i++) {
  let entry;
  try { entry = JSON.parse(lines[i]); } catch { continue; }
  const content = entry.message && entry.message.content;
  if (!Array.isArray(content)) continue;

  for (const block of content) {
    if (!block) continue;

    if (block.type === "tool_use") {
      const bp = (block.input && block.input.file_path) || "";
      const norm = normalize(bp);
      if (block.name === "Read" || EDIT_TOOLS.has(block.name)) {
        idMeta[block.id] = { name: block.name, path: norm };
      }
      if (norm !== target) continue;
      if (block.name === "Read") {
        priorReads++;
        lastActionOnTarget = "read";
        editNeedsReread = false;     // fresh Read fulfills the demand
      } else if (EDIT_TOOLS.has(block.name)) {
        lastActionOnTarget = "edit";
        editNeedsReread = false;
      }
    } else if (block.type === "tool_result") {
      const meta = block.tool_use_id ? idMeta[block.tool_use_id] : null;
      if (!meta || meta.path !== target) continue;
      if (!EDIT_TOOLS.has(meta.name)) continue;
      const c = block.content;
      const txt = Array.isArray(c)
        ? c.map(x => (x && (x.text || x.content)) || "").join(" ")
        : String(c || "");
      if ((block.is_error && READ_NEEDED_RE.test(txt)) ||
          /<tool_use_error>[^<]*has not been read/i.test(txt)) {
        editNeedsReread = true;
      }
    }
  }
}

// ─── Decision ────────────────────────────────────────────────────────────
if (priorReads === 0) process.exit(0);                // first-time read post-cutoff
if (lastActionOnTarget === "edit") process.exit(0);   // file modified → allow re-read
if (editNeedsReread) process.exit(0);                 // Edit demands fresh Read

const reason = [
  "🚧 READ DUPLICATE DETECTED — \"" + filePath + "\"",
  "",
  "File này đã Read " + priorReads + "× trong session (sau compact gần nhất nếu có),",
  "KHÔNG có Edit/Write sau đó. Nội dung vẫn còn trong context (scroll up để xem lại).",
  "",
  "Cost impact: ~$0.10-0.20 per duplicate read (cache_read tokens cho whole conversation).",
  "",
  "═══ Action ═══",
  "  • Scroll context để xem nội dung file (đã đọc rồi)",
  "  • Cần thông tin specific → dùng Grep với pattern thay vì Read full",
  "  • Edit tool báo \"File has not been read\" sau compact → hook AUTO-ALLOW Read (đã fix v2)",
  "  • File THỰC SỰ đã đổi external mà transcript chưa ghi: SKIP_READ_DEDUP=1",
  "",
  "Bypass: SKIP_READ_DEDUP=1 (per-hook) hoặc SKIP_HOOKS=1 (master).",
].join("\n");

const out = {
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: reason,
  },
};
process.stdout.write(JSON.stringify(out));
' <<< "$INPUT" 2>/dev/null)

if [[ -n "$OUT" ]]; then
  printf '%s' "$OUT"
  SPAN_DECISION="deny"
  SPAN_BYTES=${#OUT}
  FP=$(printf '%s' "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/' | tr -d '\n\t')
  SPAN_DETAIL="file=$FP"
fi

exit 0
