#!/bin/bash
# Stop hook:
#   Push Langfuse generation-create event cho mỗi assistant message MỚI trong turn vừa kết thúc.
#
# Tại sao Stop hook:
#   - Fires sau khi assistant hoàn tất 1 turn (gồm text + tool uses)
#   - transcript_path đã được flush → có thể đọc message với usage tokens + model
#
# Cursor tracking:
#   .claude/hooks/.langfuse-cursor/<safeSession>  ← lưu uuid của assistant message cuối đã push
#   → tránh push trùng nếu Stop fire nhiều lần
#
# Trace association:
#   traceId = "<safeSession>-NNN" — NNN từ filename log file hiện hành trong .session-map
#   (cùng convention với session-logger-tool.sh)

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
const transcriptPath = data.transcript_path || "";
if (!sessionId) process.exit(0);

let lf;
try { lf = require(process.env.CLAUDE_PLUGIN_ROOT ? path.join(process.env.CLAUDE_PLUGIN_ROOT, "hooks", "langfuse-helper.js") : path.join(cwd, ".claude", "hooks", "langfuse-helper.js")); }
catch (e) { process.exit(0); }
// KHÔNG gate by isConfigured — luôn enqueue + archive local. Background flush
// chỉ POST khi configured.

const safeSession = lf.safeSession(sessionId);

// ─── Skip generation flush if transcript missing, but STILL flush hook spans below ───
const hasTranscript = !!transcriptPath && fs.existsSync(transcriptPath);

// ─── Flush pending hook spans (written by enforcement hooks during UserPromptSubmit/PreToolUse) ───
// Format TSV per line: hook<TAB>decision<TAB>bytes<TAB>bypass<TAB>detail<TAB>t0_ns<TAB>tend_ns<TAB>exit_code
const pendingDir = path.join(cwd, ".claude", "hooks", ".hook-spans-pending");
const pendingFile = path.join(pendingDir, safeSession + ".tsv");
if (fs.existsSync(pendingFile)) {
  try {
    const tsvLines = fs.readFileSync(pendingFile, "utf-8").split(/\n/).filter(l => l.trim());
    const ENFORCEMENT = new Set([
      "enforce-roadmap-reading", "enforce-test-quality-checklist",
      "enforce-bmad-output-consistency", "enforce-read-dedup",
      "orchestrate-test-automation", "preload-qa-context",
    ]);
    // Resolve traceId from session-map ONCE for all pending spans
    const _mapFile = path.join(cwd, ".claude", "hooks", ".session-map", safeSession);
    let _hookTrace = safeSession + "-000";
    if (fs.existsSync(_mapFile)) {
      try {
        const lf2 = fs.readFileSync(_mapFile, "utf-8").trim();
        const mm = path.basename(lf2).match(/^prompt-(\d{3})-/);
        if (mm) _hookTrace = safeSession + "-" + mm[1];
      } catch (e) {}
    }
    for (const tsv of tsvLines) {
      const [hookName, decision, bytes, bypass, detail, t0ns, tEns, exitCode] = tsv.split(/\t/);
      if (!hookName) continue;
      const t0 = parseInt(t0ns || "0", 10);
      const tE = parseInt(tEns || "0", 10);
      const startTime = t0 > 0 ? new Date(t0 / 1e6).toISOString() : new Date().toISOString();
      const endTime   = tE > 0 ? new Date(tE / 1e6).toISOString() : new Date().toISOString();
      const durationMs = (t0 > 0 && tE > 0) ? Math.max(0, Math.round((tE - t0) / 1e6)) : 0;
      const bytesN = parseInt(bytes || "0", 10) || 0;
      lf.enqueueSpan(sessionId, {
        traceId: _hookTrace,
        name: "hook:" + hookName,
        input: { trigger: detail || null, bypass_env: bypass || null },
        output: { decision, bytes_injected: bytesN, duration_ms: durationMs, exit_code: parseInt(exitCode || "0", 10) },
        startTime, endTime,
        metadata: {
          hook_name: hookName,
          hook_kind: ENFORCEMENT.has(hookName) ? "enforcement" : "observability",
          decision,
          bypass_env: bypass || null,
          bytes_injected: bytesN,
          duration_ms: durationMs,
          exit_code: parseInt(exitCode || "0", 10),
        },
      });
    }
    fs.unlinkSync(pendingFile);
    if (process.env.LANGFUSE_DEBUG === "1") {
      process.stderr.write("[session-stop] flushed " + tsvLines.length + " hook span(s)\n");
    }
  } catch (e) {
    if (process.env.LANGFUSE_DEBUG === "1") {
      process.stderr.write("[session-stop] hook-span flush failed: " + e.message + "\n");
    }
  }
}

// ─── Below this line requires transcript; exit if missing ───
if (!hasTranscript) process.exit(0);

// ─── Derive traceId từ active prompt log file ───
const mapFile = path.join(cwd, ".claude", "hooks", ".session-map", safeSession);
let traceId = `${safeSession}-000`;
if (fs.existsSync(mapFile)) {
  try {
    const logFile = fs.readFileSync(mapFile, "utf-8").trim();
    const m = path.basename(logFile).match(/^prompt-(\d{3})-/);
    if (m) traceId = `${safeSession}-${m[1]}`;
  } catch (e) { /* skip */ }
}

// ─── Read cursor (last pushed assistant message UUID) ───
const cursorDir = path.join(cwd, ".claude", "hooks", ".langfuse-cursor");
fs.mkdirSync(cursorDir, { recursive: true });
const cursorFile = path.join(cursorDir, safeSession);
let lastUuid = "";
if (fs.existsSync(cursorFile)) {
  try { lastUuid = fs.readFileSync(cursorFile, "utf-8").trim(); } catch (e) { /* skip */ }
}

// ─── Parse transcript, collect new assistant messages ───
let lines;
try { lines = fs.readFileSync(transcriptPath, "utf-8").split("\n").filter(l => l.trim()); }
catch (e) { process.exit(0); }

const assistantMsgs = [];
let foundCursor = !lastUuid; // nếu không có cursor → include all
for (const l of lines) {
  let m;
  try { m = JSON.parse(l); } catch (e) { continue; }
  if (m.type !== "assistant" || !m.message) continue;
  if (!foundCursor) {
    if (m.uuid === lastUuid) foundCursor = true;
    continue;
  }
  assistantMsgs.push(m);
}

if (!assistantMsgs.length) process.exit(0);

// ─── Helpers ───
function extractText(content) {
  if (!Array.isArray(content)) return String(content || "");
  return content
    .filter(b => b && b.type === "text")
    .map(b => b.text || "")
    .join("\n");
}

function lastUserBefore(targetUuid) {
  // Walk transcript again, find last user message before targetUuid
  let lastUser = null;
  for (const l of lines) {
    let m;
    try { m = JSON.parse(l); } catch (e) { continue; }
    if (m.uuid === targetUuid) return lastUser;
    if (m.type === "user" && m.message) lastUser = m;
  }
  return lastUser;
}

// ─── Group assistant messages by requestId + skip empty ───
// Anthropic API trả 1 response có thể chứa MULTIPLE blocks (text + N tool_use).
// Claude Code transcript ghi mỗi block thành 1 "type:assistant" line với uuid riêng,
// nhưng TẤT CẢ chia sẻ cùng requestId + cùng `usage` (Anthropic charge 1 lần per API call).
//
// Bug v1: enqueue per msg.uuid → 76% empty output records, inflation 4-5× cost reporting.
// Fix v2: group by requestId → 1 generation per API call, gộp text từ tất cả blocks.
// Fix v3: skip empty groups (no text AND no output_tokens) → 100% non-empty records.
//
// Edge case fix v3 covers: assistant message với CHỈ tool_use blocks (no thinking text)
// và output_tokens=0. v2 vẫn enqueue (output=undefined), v3 skip entirely.
const byReq = new Map();
for (const msg of assistantMsgs) {
  const reqId = msg.requestId || msg.uuid;  // fallback uuid nếu thiếu requestId
  if (!byReq.has(reqId)) {
    byReq.set(reqId, {
      reqId,
      firstMsg: msg,
      lastMsg: msg,
      texts: [],
      uuids: [],
    });
  }
  const bucket = byReq.get(reqId);
  bucket.lastMsg = msg;
  bucket.uuids.push(msg.uuid);
  const text = extractText((msg.message || {}).content);
  if (text && text.trim()) bucket.texts.push(text);
}

// ─── Enqueue 1 generation per requestId (deterministic dedupe) ───
let pushed = 0;
let lastProcessedUuid = lastUuid;

for (const [reqId, bucket] of byReq) {
  const firstMsg = bucket.firstMsg;
  const lastMsg  = bucket.lastMsg;
  // Usage thường ở message cuối (Anthropic SDK behavior). Fallback first nếu cuối thiếu.
  const message = (lastMsg.message && lastMsg.message.usage) ? lastMsg.message : (firstMsg.message || {});
  const usage = message.usage || {};

  const userMsg = lastUserBefore(firstMsg.uuid);
  const userInput = userMsg && userMsg.message
    ? (typeof userMsg.message.content === "string"
        ? userMsg.message.content
        : extractText(userMsg.message.content))
    : "";

  const usageDetails = {
    input: usage.input_tokens || 0,
    output: usage.output_tokens || 0,
  };
  if (usage.cache_read_input_tokens)     usageDetails.cache_read_input_tokens     = usage.cache_read_input_tokens;
  if (usage.cache_creation_input_tokens) usageDetails.cache_creation_input_tokens = usage.cache_creation_input_tokens;

  // Combined text từ tất cả blocks (chỉ giữ block có text non-empty)
  const combinedOutput = bucket.texts.join("\n\n") || undefined;

  // ─── Empty-skip: nếu group KHÔNG có text AND KHÔNG có output_tokens
  // → đây là pure tool_use blocks (no LLM thinking text) → skip enqueue.
  // Lưu cursor để KHÔNG re-process nhưng KHÔNG tạo Langfuse record.
  // Note: cache_read/create tokens vẫn được Anthropic charge (request transit cost),
  // nhưng không có "generation" có ý nghĩa → không nên xuất hiện như 1 row riêng.
  const outputTokens = Number(usage.output_tokens || 0);
  if (!combinedOutput && outputTokens === 0) {
    lastProcessedUuid = bucket.uuids[bucket.uuids.length - 1];  // update cursor
    if (process.env.LANGFUSE_DEBUG === "1") {
      process.stderr.write(`[session-stop] skip empty group reqId=${reqId} (blocks=${bucket.uuids.length})\n`);
    }
    continue;
  }

  lf.enqueueGeneration(sessionId, {
    traceId,
    generationId: reqId,                    // ← per requestId, idempotent + dedupe
    name: "claude-chat",
    model: message.model || undefined,
    input: userInput || undefined,
    output: combinedOutput,
    usageDetails,
    startTime: firstMsg.timestamp || new Date().toISOString(),
    endTime: lastMsg.timestamp || new Date().toISOString(),
    metadata: {
      requestId: reqId,
      blockCount: bucket.uuids.length,        // số blocks trong API response
      firstBlockUuid: bucket.uuids[0],
      lastBlockUuid: bucket.uuids[bucket.uuids.length - 1],
      stopReason: message.stop_reason,
      serviceTier: usage.service_tier,
    },
  });

  pushed++;
  lastProcessedUuid = bucket.uuids[bucket.uuids.length - 1];  // last uuid trong group
}

// ─── Update cursor ───
try { fs.writeFileSync(cursorFile, lastProcessedUuid, "utf-8"); } catch (e) { /* skip */ }

if (process.env.LANGFUSE_DEBUG === "1") {
  process.stderr.write(`[session-stop] enqueued ${pushed} generation(s) for traceId=${traceId}\n`);
}

// Spawn background flush (only POSTs if configured) — không block Stop hook
if (lf.isConfigured()) lf.spawnBackgroundFlush(sessionId);
' <<< "$INPUT" 2>/dev/null

exit 0
