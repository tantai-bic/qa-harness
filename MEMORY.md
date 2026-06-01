# MEMORY — qa-harness state snapshot

> Snapshot trạng thái hiện tại của repo. Bổ sung cho `CLAUDE.md` (kiến trúc tĩnh) bằng các thông tin biến động: version, branch, milestone, công việc còn dang dở.
> **Last updated:** 2026-05-29

## Current state

- **Branch:** `refactor/merge-session-langfuse` (mới — tách từ `refactor/split-into-modular-plugins` HEAD `2ef62b9`)
- **Version:** `1.0.3`
- **Main:** `main`

## Marketplace structure (actual)

6 plugins sau khi merge `session` + `langfuse` → `observability`. Theo `.claude-plugin/marketplace.json`:

| # | Plugin | Vai trò chính |
|---|--------|---------------|
| 1 | `bmad-workflows` | BMAD agents + workflows + QA skills + commands + 3 runtime guards |
| 2 | `test-enforcement` | 5 pre-write quality gates + post-write run-then-fixme |
| 3 | `qa-context` | 3 UserPromptSubmit context injectors |
| 4 | `cost-control` | Read dedup (compact-aware) |
| 5 | `consumer-setup` | SessionStart setup checker |
| 6 | `observability` | Session lifecycle (5 hooks) + Langfuse telemetry/scoring (1 hook + 2 utils). Single `langfuse-helper.js` (no duplication). Granular `SKIP_LANGFUSE=1` disables Langfuse push only — session log local vẫn chạy. |

Owner: `TanTai-BIC`. Marketplace name: `qa-harness`.

## Recent milestone work

- `ae8c0ef` Split monolith `bmad-harness-plugin` → 8 modular plugins
- `8d5de0d` Finalize split: drop legacy entries, bundle BMAD guards into `bmad-workflows` (8 → 7)
- `53ae8f1` Merge `origin/main`
- `ca37707` Bump version to 1.0.3
- `2ef62b9` Release pipeline now sources version từ `package.json`
- (uncommitted on `refactor/merge-session-langfuse`) Merge `session + langfuse` → `observability` (7 → 6 plugins). Single bundled `langfuse-helper.js`. Add `SKIP_LANGFUSE` env var (granular: gate Langfuse HTTP push only, keep session logs).

## ENV — granular control của observability

| Env | Hành vi |
|-----|---------|
| `SKIP_HOOKS=1` | Master — bypass mọi hook (cũ) |
| `SKIP_LANGFUSE=1` | **MỚI** — disable Langfuse HTTP push (postBatch / flushSync / spawnBackgroundFlush early-exit qua `isConfigured()`). Session log local + enqueue + archive vẫn chạy → user có thể giữ session telemetry mà tắt vendor push. |
| `SKIP_SCORE_DETECTOR=1` | Bypass chỉ score-detector hook (cũ — vẫn còn) |
| `LANGFUSE_DEBUG=1` | Stderr verbose từ langfuse-helper (cũ) |

`langfuse-push-score.sh` + `langfuse-score-accuracy-efficiency.sh` là utility manual (user-invoked), KHÔNG gate bằng `SKIP_LANGFUSE` — user gọi explicit thì để chạy.

## Pending / not-yet-verified

- **End-to-end consumer load:** chưa chạy `claude --plugin-dir plugins/<name>` hoặc `/plugin install <name>@qa-harness` ở consumer repo Playwright. Static validation pass (JSON + bash syntax).
- **Multi-plugin coexistence:** enable cả 6 cùng lúc chưa được kiểm thử (tránh clash hook event).
- **`session-stop.sh` real Stop event:** chỉ test static với mock payload, chưa qua flow Stop thực.
- **`SKIP_LANGFUSE` integration test:** chưa verify end-to-end là HTTP push bị bypass nhưng session log vẫn ghi.
- **Commit + push branch `refactor/merge-session-langfuse`:** chưa commit, chưa PR.

## Where to look

- Static architecture & rules: `CLAUDE.md`
- Per-plugin details: `plugins/<name>/README.md` (TODO — chưa viết hết)
- Persistent auto-memory (cross-session): `~/.claude/projects/D--Automation-qa-harness/memory/MEMORY.md`
- Plugin debug recipe: auto-memory `plugin_hooks_not_loading.md`
