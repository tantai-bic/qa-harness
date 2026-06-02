#!/bin/bash
# PreToolUse hook: BLOCK đọc GitHub khi user KHÔNG yêu cầu trong prompt session.
#
# Vấn đề: Trong lúc code, agent có xu hướng tự fetch repo/PR/issue GitHub
# (qua WebFetch, WebSearch, mcp__github__*) làm scope-creep + tốn tokens
# cho content user không yêu cầu. Đặc biệt nguy hiểm khi agent vô tình
# leak data ra ngoài hoặc fetch wrong context.
#
# Logic:
#   1. Trigger: tool_name ∈ {WebFetch, WebSearch, mcp__github__*, Bash}
#   2. Filter github targets:
#        WebFetch    → url chứa github.com / githubusercontent.com / gist.github.com
#        WebSearch   → query chứa "github" / "gh "
#        mcp__github → tool name có prefix mcp__github__ (luôn là github)
#        Bash        → command:
#                       - bắt đầu `gh ` (gh CLI: pr/issue/repo/api/release/...)
#                       - `curl`/`wget`/`http`/`xh` + URL github.com|githubusercontent.com|gist|api.github
#                       - `git (fetch|pull|ls-remote|clone)` với URL/remote chứa github.com
#                       - `git (show|log|blame|rev-list|cherry|shortlog|reflog)` — commit history
#                         reads (LOCAL objects nhưng commit content originates from remote;
#                         user coi đây là "đọc github" — block by default)
#                       - `git diff <commit-ref>` — diff against commit/branch (KHÔNG block
#                         `git diff` / `git diff --cached` / `--staged` / no-arg working-tree diff)
#      Không match → exit 0 (allow, không phải github read)
#   3. Scan transcript user messages (since session start, hoặc từ compact
#      gần nhất) — tìm github-intent keyword
#   4. Có keyword → ALLOW (user đã yêu cầu)
#   5. Không có → BLOCK với reason giải thích + cho biết cách bypass
#
# Github-intent keywords (case-insensitive):
#   - "github" (raw)
#   - "gh " (gh CLI)
#   - "PR" / "pull request"
#   - "issue #<digit>"
#   - "repo " / "repository"
#   - "fork"
#   - "clone https"
#   - "gist"
#
# Bypass: SKIP_GITHUB_READ_GATE=1 (per-hook) hoặc SKIP_HOOKS=1 (master)

set -uo pipefail

SPAN_HOOK_NAME="block-github-read"
INPUT=$(cat)
SPAN_INPUT_JSON="$INPUT"
source "$(dirname "$0")/_hook-span-emit.sh"

if [[ "${SKIP_HOOKS:-0}" == "1" || "${SKIP_GITHUB_READ_GATE:-0}" == "1" ]]; then
  SPAN_DECISION="bypass"
  [[ "${SKIP_HOOKS:-0}" == "1" ]] && SPAN_BYPASS="SKIP_HOOKS" || SPAN_BYPASS="SKIP_GITHUB_READ_GATE"
  exit 0
fi

OUT=$(node -e '
const fs = require("fs");
let data;
try { data = JSON.parse(fs.readFileSync(0, "utf-8")); } catch (e) { process.exit(0); }

const toolName = data.tool_name || "";
const toolInput = data.tool_input || {};

// ─── Detect github target ────────────────────────────────────────────────
const GITHUB_HOST_RE = /github\.com|githubusercontent\.com|gist\.github\.com/i;
let githubTarget = null;

if (/^mcp__github__/.test(toolName)) {
  githubTarget = "mcp:" + toolName;
} else if (toolName === "WebFetch") {
  const url = String(toolInput.url || "");
  if (GITHUB_HOST_RE.test(url)) githubTarget = "url:" + url;
} else if (toolName === "WebSearch") {
  const q = String(toolInput.query || "");
  if (/\bgithub\b|\bgh\s/i.test(q)) githubTarget = "query:" + q;
} else if (toolName === "Bash") {
  const cmd = String(toolInput.command || "");
  // gh CLI: leading "gh " (after optional env vars/leading whitespace)
  // covers: gh pr|issue|repo|api|release|run|workflow|gist|auth ...
  const ghCli = /(^|[;&|`(\s])gh\s+(pr|issue|repo|api|release|run|workflow|gist|auth|browse|search|label|secret|ssh-key|alias|status|extension|cache|codespace|attestation|completion|config|copilot|gpg-key|org|project|ruleset|variable)\b/i;
  // curl/wget/http/xh fetching github
  const httpFetch = /(^|[;&|`(\s])(curl|wget|http|httpie|xh)\s+[^;&|`)]*?(github\.com|githubusercontent\.com|gist\.github\.com|api\.github\.com)/i;
  // git fetch/pull/ls-remote/clone with github URL inline
  const gitWithGithubUrl = /(^|[;&|`(\s])git\s+(fetch|pull|ls-remote|clone)\b[^;&|`)]*?(github\.com|githubusercontent\.com)/i;
  // git commit-history reads (LOCAL objects but commit content is remote-originated)
  const gitReadHistory = /(^|[;&|`(\s])git\s+(show|log|blame|rev-list|cherry|shortlog|reflog)\b/i;
  // git diff with commit/branch ref (skip working-tree diffs: bare `git diff`, --cached/--staged)
  // Match `git diff <something>` where <something> is not just flags or HEAD-alone working-tree
  const gitDiffRef = (function() {
    const m = cmd.match(/(^|[;&|`(\s])git\s+diff\s+([^;&|`)]*)/i);
    if (!m) return false;
    const rest = (m[2] || "").trim();
    if (!rest) return false;                            // `git diff` alone — working tree
    if (/^(--cached|--staged|--name-only|--name-status|--stat|--shortstat)(\s|$)/.test(rest)) {
      // those flags can appear alone too; check if there is a ref after the flags
      const afterFlags = rest.replace(/^(--cached|--staged|--name-only|--name-status|--stat|--shortstat)(\s+)?/g, "").trim();
      if (!afterFlags) return false;                    // `git diff --staged` — working/staged diff
      return /[a-zA-Z0-9_./~^@-]/.test(afterFlags);    // has a ref after flags → block
    }
    return /[a-zA-Z0-9_./~^@-]/.test(rest);            // has a ref → block
  })();

  if (ghCli.test(cmd)) {
    githubTarget = "bash:gh:" + cmd.trim().slice(0, 180);
  } else if (httpFetch.test(cmd)) {
    githubTarget = "bash:http:" + cmd.trim().slice(0, 180);
  } else if (gitWithGithubUrl.test(cmd)) {
    githubTarget = "bash:git-remote:" + cmd.trim().slice(0, 180);
  } else if (gitReadHistory.test(cmd)) {
    githubTarget = "bash:git-history:" + cmd.trim().slice(0, 180);
  } else if (gitDiffRef) {
    githubTarget = "bash:git-diff-ref:" + cmd.trim().slice(0, 180);
  }
}

if (!githubTarget) process.exit(0);   // not a github read → allow

// ─── Scan transcript for user intent ─────────────────────────────────────
const transcriptPath = data.transcript_path || "";
if (!transcriptPath || !fs.existsSync(transcriptPath)) process.exit(0);

let transcript;
try { transcript = fs.readFileSync(transcriptPath, "utf-8"); }
catch (e) { process.exit(0); }
const lines = transcript.split("\n").filter(Boolean);

// Reset cutoff at last compact marker (post-compact user intent must re-state)
let cutoffIdx = -1;
for (let i = 0; i < lines.length; i++) {
  try {
    const e = JSON.parse(lines[i]);
    if (e.isCompactSummary === true) cutoffIdx = i;
  } catch {}
}

// NOTE: bare \bcommit\b is TOO BROAD — matches "pre-commit hook", "commit message", etc.
// Constraints:
//   - EN: require request-verb + PLURAL "commits" (singular too overloaded with verb form)
//   - "commit <noun>" only when noun is history/hash/sha/id/log (skip "message" — noisy)
//   - VN: xem/đọc/kiểm tra/liệt kê + commit(s). Use \S (not \w — \w is ASCII only,
//     fails for diacritics like "giúp", "tra", "kê").
const INTENT_RE = new RegExp([
  "\\bgithub\\b",
  "\\bgh\\s",
  "\\bPR\\b",
  "pull\\s*request",
  "issue\\s*#\\s*\\d",
  "\\brepo(sitor(y|ies))?\\b",
  "\\bfork\\b",
  "clone\\s+https?:",
  "\\bgist\\b",
  "\\bhistory\\b",
  "\\bchangelog\\b",
  "\\bblame\\b",
  "\\breflog\\b",
  "git\\s+(show|log|blame|rev-list|cherry|shortlog|reflog|diff)\\b",
  "\\b(show|view|check|see|list|look|read|browse|inspect|peek|which|what|recent|latest)\\s+(\\S+\\s+){0,3}commits\\b",
  "\\bcommit\\s+(history|hash|sha|id|log)\\b",
  "(xem|đọc|kiểm\\s+tra|liệt\\s+kê)\\s+(\\S+\\s+){0,3}commits?\\b",
].join("|"), "i");

let userMentionedGithub = false;
for (let i = cutoffIdx + 1; i < lines.length && !userMentionedGithub; i++) {
  let entry;
  try { entry = JSON.parse(lines[i]); } catch { continue; }
  if (entry.type !== "user") continue;
  const msg = entry.message;
  if (!msg || msg.role !== "user") continue;
  const content = msg.content;
  let text = "";
  if (typeof content === "string") {
    text = content;
  } else if (Array.isArray(content)) {
    for (const block of content) {
      if (!block) continue;
      if (typeof block === "string") { text += " " + block; continue; }
      if (block.type === "text" && block.text) text += " " + block.text;
      // Skip tool_result blocks — they are NOT user intent (system-generated)
    }
  }
  if (!text) continue;
  // Strip system-reminder / command tags — those are not "user-typed" intent
  text = text
    .replace(/<system-reminder>[\s\S]*?<\/system-reminder>/gi, "")
    .replace(/<command-[^>]+>[\s\S]*?<\/command-[^>]+>/gi, "")
    .replace(/<local-command-stdout>[\s\S]*?<\/local-command-stdout>/gi, "");
  if (INTENT_RE.test(text)) userMentionedGithub = true;
}

if (userMentionedGithub) process.exit(0);   // user asked → allow

// ─── BLOCK ───────────────────────────────────────────────────────────────
const targetPreview = githubTarget.length > 200 ? githubTarget.slice(0, 200) + "…" : githubTarget;
const reason = [
  "🚧 GITHUB READ BLOCKED — \"" + toolName + "\"",
  "",
  "Tool đang cố ĐỌC GitHub nhưng user CHƯA yêu cầu trong prompt session này:",
  "  Target: " + targetPreview,
  "",
  "Lý do gate: tránh agent tự ý fetch repo/PR/issue ngoài scope user request,",
  "leak unrelated context vào conversation, hoặc waste tokens cho content",
  "user không cần.",
  "",
  "═══ Action ═══",
  "  • Nếu user THỰC SỰ đã yêu cầu → user reprompt với keyword rõ ràng:",
  "    \"github\", \"PR\", \"repo\", \"commit\", \"history\", \"git show/log/blame\"",
  "  • Bash bị block: `gh pr/issue/repo/api`, `curl github.com/...`,",
  "    `git fetch/pull` URL github, `git show|log|blame|rev-list|cherry|shortlog|reflog`,",
  "    `git diff <commit-ref>`.",
  "  • Working-tree diffs vẫn pass: `git diff`, `git diff --cached`, `git diff --staged`.",
  "  • Local non-history reads vẫn pass: `git status`, `git branch`, `git rev-parse HEAD`.",
  "  • Nếu chỉ là agent suy đoán cần github → SKIP, tiếp tục với context",
  "    local đã có (read source / grep / git log).",
  "  • One-shot bypass khi user xác nhận cần fetch: SKIP_GITHUB_READ_GATE=1",
  "",
  "Bypass: SKIP_GITHUB_READ_GATE=1 (per-hook) hoặc SKIP_HOOKS=1 (master).",
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
  TN=$(printf '%s' "$INPUT" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"([^"]+)"$/\1/' | tr -d '\n\t')
  SPAN_DETAIL="tool=$TN"
fi

exit 0
