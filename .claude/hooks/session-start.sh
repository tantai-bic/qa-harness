#!/bin/bash
# SessionStart hook:
#   Fire ONE time khi session khởi tạo (trước khi user gửi prompt đầu tiên).
#   Push trace "session-init" riêng lên Langfuse với env snapshot + source matcher
#   (startup / resume / clear / compact) để tách startup overhead khỏi cost prompt #1.
#
# Trace ID convention: <safeSession>-init (KHÔNG đụng với <safeSession>-NNN của prompts).
#
# Bypass: SKIP_HOOKS=1 (master) — vẫn enqueue local archive, chỉ skip push.

set -uo pipefail

# Load .env — .env wins over shell env (cùng pattern với session-logger-init.sh)
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

# Capture shell-side env snapshot (Node sẽ JSON-encode qua process.env)
export _SS_OS_UNAME="$(uname -a 2>/dev/null || echo "${OS:-unknown}")"
export _SS_NODE_VERSION="$(node -v 2>/dev/null || echo "n/a")"
export _SS_GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "n/a")"
export _SS_GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo "n/a")"
export _SS_GIT_DIRTY="$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
export _SS_HOSTNAME="$(hostname 2>/dev/null || echo "n/a")"

node -e '
const fs = require("fs");
const path = require("path");

let data;
try { data = JSON.parse(fs.readFileSync(0, "utf-8")); }
catch (e) { process.exit(0); }

const sessionId      = data.session_id     || ("no-session-" + process.pid);
const source         = data.source         || "unknown";   // startup | resume | clear | compact
const transcriptPath = data.transcript_path || null;
// Always use process.cwd() — payload data.cwd có thể là POSIX path trên Git Bash
// mà path.join sẽ mangle với backslash-style Windows segments.
const cwd            = process.cwd();

const safeSession = String(sessionId).replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 64) || "unknown";

// ─── Parse settings.json để biết hooks + MCP servers enabled ───────────────
let hooksEnabled = [];
let mcpDisabled  = [];
try {
  const settingsPath = path.join(cwd, ".claude", "settings.json");
  if (fs.existsSync(settingsPath)) {
    const s = JSON.parse(fs.readFileSync(settingsPath, "utf-8"));
    if (s.hooks) {
      for (const evt of Object.keys(s.hooks)) {
        for (const grp of (s.hooks[evt] || [])) {
          for (const h of (grp.hooks || [])) {
            if (h.command) {
              const m = h.command.match(/([a-z0-9-]+)\.sh/i);
              if (m) hooksEnabled.push(`${evt}:${m[1]}`);
            }
          }
        }
      }
    }
    mcpDisabled = s.disabledMcpjsonServers || [];
  }
} catch (e) { /* ignore parse errors */ }

// ─── Count prior sessions trong repo này (để biết đây là session thứ mấy) ──
let priorSessionsCount = 0;
try {
  const sessionsDir = path.join(cwd, ".claude", "session-logs");
  if (fs.existsSync(sessionsDir)) {
    priorSessionsCount = fs.readdirSync(sessionsDir)
      .filter(n => n !== safeSession)
      .filter(n => {
        try {
          const st = fs.statSync(path.join(sessionsDir, n));
          return st.isDirectory();
        } catch (e) { return false; }
      })
      .length;
  }
} catch (e) { /* ignore */ }

// ─── Build env snapshot ────────────────────────────────────────────────────
const harnessOff = process.env.SKIP_HOOKS === "1";
const lfConfigured = !!(process.env.LANGFUSE_PUBLIC_KEY && process.env.LANGFUSE_SECRET_KEY);

const envSnapshot = {
  source,
  transcript_path: transcriptPath,
  cwd,
  hostname:        process.env._SS_HOSTNAME || "n/a",
  os:              process.env._SS_OS_UNAME || "unknown",
  node_version:    process.env._SS_NODE_VERSION || "n/a",
  git_branch:      process.env._SS_GIT_BRANCH || "n/a",
  git_commit:      process.env._SS_GIT_COMMIT || "n/a",
  git_dirty_files: parseInt(process.env._SS_GIT_DIRTY || "0", 10),
  user:            process.env.USER || process.env.USERNAME || "n/a",
  model:           process.env.CLAUDECODE_MODEL || process.env.CLAUDE_MODEL || "n/a",
  langfuse_configured: lfConfigured,
  langfuse_host:   process.env.LANGFUSE_HOST || "default",
  harness_off:     harnessOff,
  skip_flags: {
    SKIP_HOOKS:           process.env.SKIP_HOOKS === "1",
    SKIP_READ_DEDUP:      process.env.SKIP_READ_DEDUP === "1",
    SKIP_BMAD_OUTPUT:     process.env.SKIP_BMAD_OUTPUT === "1",
    LANGFUSE_DEBUG:       process.env.LANGFUSE_DEBUG === "1",
  },
  hooks_enabled:        hooksEnabled,
  mcp_servers_disabled: mcpDisabled,
  prior_sessions_in_repo: priorSessionsCount,
  session_init_ts: new Date().toISOString(),
};

// ─── Ensure session dir tồn tại + ghi _meta.txt sớm hơn (trước prompt #1) ──
const sessionDir = path.join(cwd, ".claude", "session-logs", safeSession);
fs.mkdirSync(sessionDir, { recursive: true });
const metaFile = path.join(sessionDir, "_meta.txt");
if (!fs.existsSync(metaFile)) {
  const meta = [
    `session_id:  ${sessionId}`,
    `created:     ${envSnapshot.session_init_ts}`,
    `source:      ${source}`,
    `cwd:         ${cwd}`,
    `git_branch:  ${envSnapshot.git_branch}`,
    `git_commit:  ${envSnapshot.git_commit}`,
    `model:       ${envSnapshot.model}`,
    `hostname:    ${envSnapshot.hostname}`,
  ].join("\n") + "\n";
  fs.writeFileSync(metaFile, meta, "utf-8");
}

// ─── Build trace tags ──────────────────────────────────────────────────────
const tags = [
  "session-start",
  `source:${source}`,
  harnessOff ? "harness-off" : "harness",
  lfConfigured ? "lf-configured" : "lf-missing-creds",
];

const sourceIcon = ({ startup: "🟢", resume: "🔁", clear: "🧹", compact: "🗜️" })[source] || "🟢";
const traceName = `${sourceIcon} session-start · ${source}`;

// ─── Enqueue Langfuse trace (luôn enqueue → local archive + queue retry) ───
try {
  const lf = require(path.join(cwd, ".claude", "hooks", "langfuse-helper.js"));
  lf.enqueueTrace(sessionId, {
    traceId: `${safeSession}-init`,
    name: traceName,
    input: { source, transcript_path: transcriptPath, cwd },
    metadata: envSnapshot,
    tags,
  });
  if (lf.isConfigured()) {
    lf.spawnBackgroundFlush(sessionId);
  }
} catch (e) {
  if (process.env.LANGFUSE_DEBUG === "1") {
    process.stderr.write(`[session-start] langfuse skipped: ${e.message}\n`);
  }
}
' <<< "$INPUT" 2>/dev/null

exit 0
