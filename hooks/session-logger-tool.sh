#!/bin/bash
# PostToolUse hook:
#   1. Append tool call detail vào ACTIVE prompt log của session.
#   2. Enqueue Langfuse span-create event dưới trace của prompt hiện hành.
#
# Active prompt = file được session-logger-init.sh tạo gần nhất cho session_id này.
# Đường dẫn lookup qua .claude/hooks/.session-map/<safeSessionId>.
# traceId của Langfuse derive từ tên file: prompt-NNN-*.log → "<safeSession>-NNN".

set -uo pipefail

INPUT=$(cat)

node -e '
const fs = require("fs");
const path = require("path");

let data;
try { data = JSON.parse(fs.readFileSync(0, "utf-8")); }
catch (e) { process.exit(0); }

const cwd         = process.cwd();
const sessionId   = data.session_id || ("no-session-" + process.pid);
const safeSession = String(sessionId).replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 64) || "unknown";
const mapFile     = path.join(cwd, ".claude", "hooks", ".session-map", safeSession);
if (!fs.existsSync(mapFile)) process.exit(0);

const logFile = fs.readFileSync(mapFile, "utf-8").trim();
if (!logFile || !fs.existsSync(logFile)) process.exit(0);

const MAX_IN  = 1200;
const MAX_OUT = 3000;

const truncate = (val, max) => {
  const s = typeof val === "string" ? val : JSON.stringify(val, null, 2) || "";
  return s.length > max
    ? s.slice(0, max) + `\n  … [truncated ${s.length - max} chars]`
    : s;
};

const indent = (text, prefix) =>
  String(text).split("\n").map(l => prefix + l).join("\n");

const ICONS = {
  Read: "📖", Write: "✍️ ", Edit: "✏️ ", Bash: "🖥️ ",
  Grep: "🔍", Glob: "📂", Agent: "🤖", WebSearch: "🌐",
  WebFetch: "🌍", TaskCreate: "📋", TaskUpdate: "📋",
  TaskGet: "📋", Plan: "📐", Skill: "🎯",
};
const toolName  = data.tool_name || "unknown";
const icon      = Object.entries(ICONS).find(([k]) => toolName.startsWith(k))?.[1] ?? "🔧";
const inputObj  = data.tool_input || {};
const outputVal = data.tool_response ?? "";
const inputStr  = JSON.stringify(inputObj, null, 2);
const outputStr = typeof outputVal === "string"
  ? outputVal
  : JSON.stringify(outputVal, null, 2);

const now  = new Date();
const startTime = now.toISOString();
const pad  = n => String(n).padStart(2, "0");
const time = `${pad(now.getHours())}:${pad(now.getMinutes())}:${pad(now.getSeconds())}`;

const entry = [
  `[${time}]  ${icon} ${toolName}`,
  "  ┌─ INPUT",
  indent(truncate(inputStr, MAX_IN), "  │  "),
  "  ├─ OUTPUT",
  indent(truncate(outputStr, MAX_OUT), "  │  "),
  "  └" + "─".repeat(66),
  "",
].join("\n");

fs.appendFileSync(logFile, entry, "utf-8");
try { fs.utimesSync(mapFile, now, now); } catch (e) { /* skip */ }

// ─── Langfuse span enqueue (luôn enqueue → archive local + queue retry) ───
try {
  const lf = require(process.env.CLAUDE_PLUGIN_ROOT ? path.join(process.env.CLAUDE_PLUGIN_ROOT, "hooks", "langfuse-helper.js") : path.join(cwd, ".claude", "hooks", "langfuse-helper.js"));
  // Derive traceId from active log file: prompt-NNN-*.log → "<safeSession>-NNN"
  const m = path.basename(logFile).match(/^prompt-(\d{3})-/);
  const idx = m ? m[1] : "000";
  const traceId = `${safeSession}-${idx}`;
  lf.enqueueSpan(sessionId, {
    traceId,
    name: toolName,
    input: inputObj,
    output: outputVal,
    startTime,
    endTime: new Date().toISOString(),
    metadata: { tool: toolName },
  });
} catch (e) {
  if (process.env.LANGFUSE_DEBUG === "1") {
    process.stderr.write(`[session-logger-tool] langfuse skipped: ${e.message}\n`);
  }
}
' <<< "$INPUT" 2>/dev/null

exit 0
