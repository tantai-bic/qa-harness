#!/bin/bash
# UserPromptSubmit hook:
#   1. Tách mỗi prompt vào file riêng:
#        .claude/session-logs/<session-id>/prompt-NNN-{ts}.log
#   2. Tool calls (do session-logger-tool.sh fire) sẽ append vào file prompt
#      hiện hành (active prompt log).
#   3. Cleanup map entries của sessions đã inactive (mtime > SESSION_MAP_TTL_HOURS,
#      default 24h).
#   4. Enqueue Langfuse trace-create event + spawn background flush (nếu
#      LANGFUSE_PUBLIC_KEY + LANGFUSE_SECRET_KEY set).
#
# Map layout:
#   .claude/hooks/.session-map/<session-id>  ← chứa absolute path tới active prompt log
#
# Race-safety: dùng session_id từ Claude hook payload (không phải timestamp + .current-log).

set -uo pipefail

# Load .env — .env wins over shell env (skip empty values)
if [[ -f ".env" ]]; then
  shopt -s extglob
  while IFS= read -r _ln || [[ -n "$_ln" ]]; do
    [[ -z "$_ln" || "$_ln" =~ ^[[:space:]]*# ]] && continue
    _k="${_ln%%=*}"; _k="${_k//[[:space:]]/}"
    _v="${_ln#*=}";  _v="${_v##*( )}"; _v="${_v%%*( )}"
    _v="${_v#\'}"; _v="${_v%\'}"; _v="${_v#\"}"; _v="${_v%\"}"
    [[ -n "$_k" && -n "$_v" ]] && export "$_k"="$_v"
  done < .env
fi

INPUT=$(cat)

SESSION_MAP_TTL_HOURS="${SESSION_MAP_TTL_HOURS:-24}"

# ─── Cleanup inactive session-map entries (cheap, runs each init) ───────────
node -e '
const fs = require("fs");
const path = require("path");
const cwd = process.cwd();
const mapDir = path.join(cwd, ".claude", "hooks", ".session-map");
if (!fs.existsSync(mapDir)) process.exit(0);

const ttlHours = parseFloat(process.argv[1]);
if (!Number.isFinite(ttlHours) || ttlHours <= 0) process.exit(0);

const cutoff = Date.now() - ttlHours * 3600 * 1000;
let removed = 0;
for (const name of fs.readdirSync(mapDir)) {
  const f = path.join(mapDir, name);
  try {
    const st = fs.statSync(f);
    if (st.isFile() && st.mtimeMs < cutoff) {
      fs.unlinkSync(f);
      removed++;
    }
  } catch (e) { /* skip */ }
}
if (process.env.SESSION_MAP_DEBUG === "1" && removed > 0) {
  process.stderr.write(`[session-logger] cleaned ${removed} inactive map entries (>${ttlHours}h)\n`);
}
' "$SESSION_MAP_TTL_HOURS" 2>/dev/null

# ─── Create new prompt log file + Langfuse trace enqueue ────────────────────
node -e '
const fs = require("fs");
const path = require("path");

let data;
try { data = JSON.parse(fs.readFileSync(0, "utf-8")); }
catch (e) { process.exit(0); }

const prompt    = data.prompt    || "";
const sessionId = data.session_id || ("no-session-" + process.pid);
const cwd       = process.cwd();

const safeSession = String(sessionId).replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 64) || "unknown";

const sessionDir = path.join(cwd, ".claude", "session-logs", safeSession);
const mapDir     = path.join(cwd, ".claude", "hooks", ".session-map");
fs.mkdirSync(sessionDir, { recursive: true });
fs.mkdirSync(mapDir, { recursive: true });

const existing = fs.readdirSync(sessionDir).filter(n => /^prompt-\d{3}-.*\.log$/.test(n));
const nextIdx  = existing.length + 1;
const idxStr   = String(nextIdx).padStart(3, "0");

const now = new Date();
const pad = n => String(n).padStart(2, "0");
const ts  = `${now.getFullYear()}-${pad(now.getMonth()+1)}-${pad(now.getDate())}_` +
            `${pad(now.getHours())}-${pad(now.getMinutes())}-${pad(now.getSeconds())}`;

const promptFile = path.join(sessionDir, `prompt-${idxStr}-${ts}.log`);

if (nextIdx === 1) {
  const metaFile = path.join(sessionDir, "_meta.txt");
  const meta = [
    `session_id: ${sessionId}`,
    `created:    ${now.toISOString()}`,
    `cwd:        ${cwd}`,
  ].join("\n") + "\n";
  fs.writeFileSync(metaFile, meta, "utf-8");
}

const L = "═".repeat(72);
const D = "─".repeat(72);
const header = [
  L,
  `📝  PROMPT #${nextIdx}`,
  `🆔  SESSION  : ${sessionId}`,
  `📅  TIME     : ${now.toISOString()}`,
  L,
  "",
  prompt,
  "",
  D,
  "🔧  TOOL CALLS",
  D,
  "",
].join("\n");

fs.writeFileSync(promptFile, header, "utf-8");

const mapFile = path.join(mapDir, safeSession);
fs.writeFileSync(mapFile, promptFile, "utf-8");

// ─── Detect tags để filter trace trên Langfuse dashboard ───
// Multi-axis tagging cho ad-hoc filter:
//   - harness/harness-off    : hooks ON/OFF
//   - bmad / bmad-agent:<x>  : bmad activation
//   - task:<type>            : semantic category (test-writing/scoring/debug/...)
//   - domain:<phase>         : Phase A/B/C/D mapping
//   - slash:<cmd>            : first slash command nếu có
//   - psig:<hash>            : prompt signature (6-char hash của normalized prompt)
//                              → filter "prompt giống nhau" qua psig đồng nhất
const traceTags = [];
const skipHooks = process.env.SKIP_HOOKS === "1";
traceTags.push(skipHooks ? "harness-off" : "harness");

// ─── Project tag (env override → consumer config → plugin config → cwd basename) ──
function slugifyProjectTag(s) {
  return String(s).toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "") || "unknown";
}
function resolveProjectName() {
  const envOverride = process.env.LANGFUSE_PROJECT_TAG;
  if (envOverride && envOverride.trim()) return envOverride.trim();
  const candidates = [path.join(cwd, "_bmad", "bmm", "config.yaml")];
  if (process.env.CLAUDE_PLUGIN_ROOT) {
    candidates.push(path.join(process.env.CLAUDE_PLUGIN_ROOT, "_bmad", "bmm", "config.yaml"));
  }
  for (const f of candidates) {
    try {
      const m = fs.readFileSync(f, "utf-8").match(/^\s*project_name\s*:\s*(.+?)\s*$/m);
      if (m) {
        const name = m[1].replace(/^["\x27]+|["\x27]+$/g, "").trim();
        if (name) return name;
      }
    } catch (_) {}
  }
  return path.basename(cwd) || "unknown";
}
traceTags.push(`project:${slugifyProjectTag(resolveProjectName())}`);

// ─── bmad detection (existing) ───
const bmadPatterns = [
  /\/bmad:/i,
  /bmad:bmm:agents:/i,
  /<command-name>\/?bmad:/i,
  /embody this agent.s persona/i,
  /<agent\s+id="[^"]+\.agent\.yaml"/i,
  /\b_bmad\/bmm\/agents\//i,
];
if (bmadPatterns.some((re) => re.test(prompt))) traceTags.push("bmad");
const agentMatch = prompt.match(/(?:bmad:bmm:agents:|_bmad\/bmm\/agents\/)([a-z-]+)/i);
if (agentMatch && traceTags.includes("bmad")) traceTags.push(`bmad-agent:${agentMatch[1].toLowerCase()}`);

// ─── task-type detection (semantic category) ───
const lcPrompt = prompt.toLowerCase();
const taskTypePatterns = [
  // Order matters: more specific first
  [/score\b.*trace|chấm điểm|đánh giá.*(?:trace|phiên|langfuse)|rate session/i, "scoring"],
  [/viết test|tạo test|generate test|làm test|write test|create test|\.spec\.ts/i, "test-writing"],
  [/update.*hook|sửa.*hook|implement.*hook|enforce-/i, "hook-update"],
  [/debug|tại sao|why\b|root cause|fix bug|sửa lỗi/i, "debug"],
  [/refactor|restructure|reorganize|sắp xếp lại/i, "refactor"],
  [/cost|optimize|improve.*cost|tiết kiệm|cải thiện/i, "optimize"],
  [/đọc|read\b.*doc|review|inspect|tìm hiểu/i, "research"],
  [/log bug|bug log|template.*bug/i, "bug-logging"],
  [/run test|chạy test|playwright test|npm.*test/i, "test-execution"],
];
for (const [re, type] of taskTypePatterns) {
  if (re.test(prompt) || re.test(lcPrompt)) {
    traceTags.push(`task:${type}`);
    break;
  }
}

// ─── domain detection (generic — consumer override via env DOMAIN_PATTERNS_JSON) ───
// JSON shape: [[regex_string, domain_label], ...]
// vd: DOMAIN_PATTERNS_JSON='[["phase\\s*a|refinement","phase-a"]]'
try {
  const userDomains = JSON.parse(process.env.DOMAIN_PATTERNS_JSON || "[]");
  for (const [reStr, domain] of userDomains) {
    try {
      if (new RegExp(reStr, "i").test(prompt)) {
        traceTags.push(`domain:${domain}`);
        break;
      }
    } catch {}
  }
} catch {}

// ─── slash command detection ───
const slashMatch = prompt.match(/^\s*\/([a-z][a-z0-9_:-]{0,30})/i);
if (slashMatch) {
  // Special bmad already tagged, skip
  if (!slashMatch[1].toLowerCase().startsWith("bmad")) {
    traceTags.push(`slash:${slashMatch[1].toLowerCase()}`);
  }
}

// ─── prompt signature (6-char hash) — group EXACT-similar prompts ───
// Normalize: lowercase + collapse whitespace + strip trailing punctuation + strip dates
const normalized = prompt
  .toLowerCase()
  .replace(/\d{4}-\d{2}-\d{2}/g, "")              // dates
  .replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/g, "")  // UUIDs
  .replace(/\d+/g, "")                              // numbers (preserve structure)
  .replace(/[^\p{L}\p{N}\s]/gu, " ")               // punctuation → space (preserve unicode letters)
  .replace(/\s+/g, " ")
  .trim()
  .slice(0, 200);                                  // cap để hash deterministic

if (normalized.length >= 10) {
  const crypto = require("crypto");
  const psig = crypto.createHash("sha256").update(normalized).digest("hex").slice(0, 6);
  traceTags.push(`psig:${psig}`);
}

// ─── Build descriptive trace name (KHÔNG dùng "Prompt #N" mơ hồ) ───
// Format: "#N · <short summary>"
// - N      = prompt index
// - summary = first non-blank line, normalize whitespace, strip slash commands,
//             limit 70 chars để Langfuse dashboard list dễ scan.
function buildTraceName(idx, raw) {
  const text = String(raw || "").trim();
  if (!text) return `#${idx} · (empty prompt)`;

  // Special case: bmad slash command → "#N · bmad:<agent>"
  const bmadSlash = text.match(/^\s*\/bmad(?::[a-z0-9-]+)+:agents:([a-z][a-z0-9-]*)/i);
  if (bmadSlash) return `#${idx} · /bmad agent:${bmadSlash[1].toLowerCase()}`;

  // Special case: other slash commands → "#N · /<command>"
  const slashCmd = text.match(/^\s*\/([a-z][a-z0-9_:-]*)/i);
  if (slashCmd) return `#${idx} · /${slashCmd[1]} ${text.replace(/^\s*\/\S+\s*/, "").slice(0, 50)}`.trim();

  // Default: first line, collapse whitespace, slice
  const firstLine = text.split(/\r?\n/).find(l => l.trim()) || text;
  const cleaned = firstLine.replace(/\s+/g, " ").trim();
  const max = 70;
  const summary = cleaned.length > max ? cleaned.slice(0, max - 1) + "…" : cleaned;
  return `#${idx} · ${summary}`;
}
const traceName = buildTraceName(nextIdx, prompt);

// ─── Langfuse trace enqueue (luôn enqueue → archive local + queue retry) ───
// Background flush chỉ POST khi LANGFUSE_PUBLIC_KEY + SECRET_KEY set.
try {
  const lf = require(process.env.CLAUDE_PLUGIN_ROOT ? path.join(process.env.CLAUDE_PLUGIN_ROOT, "hooks", "langfuse-helper.js") : path.join(cwd, ".claude", "hooks", "langfuse-helper.js"));
  const traceId = `${safeSession}-${idxStr}`;
  lf.enqueueTrace(sessionId, {
    traceId,
    name: traceName,
    input: prompt,
    metadata: {
      cwd,
      promptIndex: nextIdx,
      sourceLogFile: promptFile,
      harness: !skipHooks,
      bmad: traceTags.includes("bmad"),
      bmadAgent: agentMatch && traceTags.includes("bmad") ? agentMatch[1].toLowerCase() : undefined,
    },
    tags: traceTags,
  });
  if (lf.isConfigured()) {
    lf.spawnBackgroundFlush(sessionId);

    // Orphan-queue sweep: flush queue file của session khác đã idle ≥ ORPHAN_IDLE_MIN phút.
    // Tránh trường hợp session cũ crash/force-close → queue tồn tại mãi (không push được lên Langfuse).
    // Disable: LANGFUSE_SWEEP_ORPHANS=0
    if (process.env.LANGFUSE_SWEEP_ORPHANS !== "0") {
      const orphanIdleMin = parseFloat(process.env.LANGFUSE_ORPHAN_IDLE_MIN || "10");
      const queueDir = path.join(cwd, ".claude", "hooks", ".langfuse-queue");
      if (fs.existsSync(queueDir)) {
        const cutoff = Date.now() - orphanIdleMin * 60 * 1000;
        for (const name of fs.readdirSync(queueDir)) {
          if (!name.endsWith(".jsonl")) continue;
          const otherSid = name.replace(/\.jsonl$/, "");
          if (otherSid === safeSession) continue;
          try {
            const st = fs.statSync(path.join(queueDir, name));
            if (st.isFile() && st.mtimeMs < cutoff) {
              lf.spawnBackgroundFlush(otherSid);
            }
          } catch (e) { /* skip */ }
        }
      }
    }
  }
} catch (e) {
  if (process.env.LANGFUSE_DEBUG === "1") {
    process.stderr.write(`[session-logger-init] langfuse skipped: ${e.message}\n`);
  }
}
' <<< "$INPUT" 2>/dev/null

exit 0
