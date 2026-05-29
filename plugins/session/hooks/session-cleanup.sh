#!/bin/bash
# SessionEnd hook:
#   1. Flush queued Langfuse events (synchronous — đây là cơ hội cuối để push).
#   2. Xóa map entry của session vừa kết thúc.
#   3. Logs (.claude/session-logs/<id>/) giữ nguyên cho history.
#
# TTL-based cleanup (24h) trong session-logger-init.sh vẫn giữ làm safety net cho
# trường hợp SessionEnd không fire (crash, force-kill, etc.).

set -uo pipefail

INPUT=$(cat)

node -e '
const fs = require("fs");
const path = require("path");

let data;
try { data = JSON.parse(fs.readFileSync(0, "utf-8")); }
catch (e) { process.exit(0); }

const cwd = process.cwd();
const sessionId = data.session_id || "";
if (!sessionId) process.exit(0);

const safeSession = String(sessionId).replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 64) || "unknown";
const mapFile = path.join(cwd, ".claude", "hooks", ".session-map", safeSession);

function finish() {
  // Remove map entry + Langfuse cursor (logs giữ nguyên)
  try {
    if (fs.existsSync(mapFile)) {
      fs.unlinkSync(mapFile);
      if (process.env.SESSION_MAP_DEBUG === "1") {
        process.stderr.write(`[session-cleanup] removed ${safeSession} on SessionEnd\n`);
      }
    }
  } catch (e) { /* skip */ }

  try {
    const cursorFile = path.join(cwd, ".claude", "hooks", ".langfuse-cursor", safeSession);
    if (fs.existsSync(cursorFile)) fs.unlinkSync(cursorFile);
  } catch (e) { /* skip */ }
}

// Langfuse synchronous flush — block tới khi xong (hoặc HTTP timeout 10s)
try {
  const lf = require(process.env.CLAUDE_PLUGIN_ROOT ? path.join(process.env.CLAUDE_PLUGIN_ROOT, "hooks", "langfuse-helper.js") : path.join(cwd, ".claude", "hooks", "langfuse-helper.js"));
  if (lf.isConfigured()) {
    lf.flushSync(sessionId, () => finish());
  } else {
    finish();
  }
} catch (e) {
  if (process.env.LANGFUSE_DEBUG === "1") {
    process.stderr.write(`[session-cleanup] langfuse skipped: ${e.message}\n`);
  }
  finish();
}
' <<< "$INPUT" 2>/dev/null

exit 0
