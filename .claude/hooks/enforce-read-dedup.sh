#!/bin/bash
# PreToolUse hook: BLOCK Read duplicate trong cùng session.
#
# Vấn đề observed (trace 89fee3f7):
#   • refinement.fixture.ts đọc 4× → waste ~$0.30
#   • campaign.service.ts đọc 2× → waste ~$0.10
#   • error.types.ts đọc 2× → waste ~$0.10
#   Total dup waste: ~$0.50/session
#
# Logic:
#   1. Trigger: tool_name=Read + file_path
#   2. Scan transcript JSONL → tìm prior Read calls cùng file_path
#   3. Nếu đã Read + KHÔNG có Edit/Write/MultiEdit trên file đó SAU lần Read cuối
#      → BLOCK (content vẫn nguyên trong context)
#   4. Nếu có Edit/Write giữa các Read → ALLOW (file đã đổi, re-read hợp lệ)
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

// Normalize path (Windows backslash + Unix slash, case-insensitive)
const normalize = (p) => String(p).toLowerCase().replace(/\\\\/g, "/").replace(/\/+/g, "/");
const target = normalize(filePath);

// Scan transcript → track Read/Edit/Write actions on target file (in order)
let transcript;
try { transcript = fs.readFileSync(transcriptPath, "utf-8"); }
catch (e) { process.exit(0); }
const lines = transcript.split("\n").filter(Boolean);

let priorReads = 0;
let lastActionOnTarget = null;  // "read" | "edit" | null
const EDIT_TOOLS = new Set(["Edit", "Write", "MultiEdit", "NotebookEdit"]);

for (const line of lines) {
  let entry;
  try { entry = JSON.parse(line); } catch (e) { continue; }
  if (entry.type !== "assistant" || !entry.message) continue;
  const content = entry.message.content;
  if (!Array.isArray(content)) continue;
  for (const block of content) {
    if (!block || block.type !== "tool_use") continue;
    const blockPath = (block.input && block.input.file_path) || "";
    if (normalize(blockPath) !== target) continue;
    if (block.name === "Read") {
      priorReads++;
      lastActionOnTarget = "read";
    } else if (EDIT_TOOLS.has(block.name)) {
      lastActionOnTarget = "edit";
    }
  }
}

// First-time read OR file modified since last read → allow
if (priorReads === 0 || lastActionOnTarget === "edit") process.exit(0);

// Duplicate read detected (no modification since)
const reason = [
  "🚧 READ DUPLICATE DETECTED — \"" + filePath + "\"",
  "",
  "File này đã Read " + priorReads + "× trong session, KHÔNG có Edit/Write sau đó.",
  "Nội dung vẫn còn trong context (scroll up để xem lại).",
  "",
  "Cost impact: ~$0.10-0.20 per duplicate read (cache_read tokens cho whole conversation).",
  "Observed: trace 89fee3f7 đã waste ~$0.50 với 5 dup reads tương tự.",
  "",
  "═══ Action ═══",
  "  • Scroll context để xem nội dung file (đã đọc rồi)",
  "  • Nếu cần thông tin specific → dùng Grep với pattern thay vì Read full",
  "  • Nếu file THỰC SỰ đã đổi mà transcript chưa ghi (race condition):",
  "    set SKIP_READ_DEDUP=1 trước khi retry",
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
  # Extract file_path from input for detail
  FP=$(printf '%s' "$INPUT" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/' | tr -d '\n\t')
  SPAN_DETAIL="file=$FP"
fi
# else: SPAN_DECISION stays "skip" (allowed read — first-time or file changed)

exit 0
