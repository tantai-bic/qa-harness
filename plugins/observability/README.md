# observability

Session lifecycle logging and Langfuse telemetry for Claude Code sessions. Tracks every prompt, tool call, and assistant response.

## What it does

Six hooks cover the full session lifecycle:

| Hook | Event | Action |
|------|-------|--------|
| `session-start.sh` | SessionStart (startup\|resume\|clear\|compact) | Push `session-start` trace to Langfuse with env snapshot (git branch, model, hooks enabled) |
| `session-logger-init.sh` | UserPromptSubmit | Initialize log file for the current prompt |
| `langfuse-score-detector.sh` | UserPromptSubmit | Detect scoring opportunities and queue score events |
| `session-logger-tool.sh` | PostToolUse | Log each tool execution to session log |
| `session-stop.sh` | Stop | Push generation events (grouped by `requestId`) + flush hook spans to Langfuse |
| `session-cleanup.sh` | SessionEnd | Final cleanup of session state |

Two manual utilities (not registered as hooks):

| Script | Usage |
|--------|-------|
| `langfuse-push-score.sh` | Push scores to a trace (single or batch matrix) |
| `langfuse-score-accuracy-efficiency.sh` | Compute accuracy × token efficiency × cost score |

## Local storage

All data is archived locally regardless of Langfuse configuration:

```
.claude/session-logs/<safeSession>/         # session logs per prompt
.claude/hooks/.langfuse-queue/<session>.jsonl  # events pending push
.claude/hooks/.langfuse-cursor/<session>       # dedup cursor
.claude/hooks/.hook-spans-pending/<session>.tsv  # enforcement hook spans
```

## Langfuse setup

Create `.env` at the consumer project root:

```bash
LANGFUSE_PUBLIC_KEY=pk-lf-xxxxxxxxxxxxxxxx
LANGFUSE_SECRET_KEY=sk-lf-xxxxxxxxxxxxxxxx
LANGFUSE_HOST=https://cloud.langfuse.com    # or self-host URL
```

The `.env` file is loaded automatically by all hooks.

## What gets pushed to Langfuse

**On session start:** trace with tags `session-start`, `source:<startup|resume|compact>`, `project:<name>` and metadata: git branch/commit, model, node version, hooks enabled, prior session count.

**After each turn:** one `generation` per API `requestId` (deduplicated) with input (user prompt), output (assistant text), and full token breakdown (`input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`).

**Hook spans:** `enforce-read-dedup`, `enforce-test-quality-checklist`, `enforce-roadmap-reading`, etc. — each with `decision` (allow/block), `bytes_injected`, `duration_ms`.

## Push score manually

```bash
# Single score
bash .claude/hooks/langfuse-push-score.sh \
  --trace-id <traceId> \
  --name "overall-quality" \
  --value 0.9 \
  --comment "Production-ready"

# Batch via template
bash .claude/hooks/langfuse-push-score.sh \
  --trace-id <traceId> \
  --template test-quality \
<< 'EOF'
{
  "convention-adherence": [1.0, "Correct fixture + path alias"],
  "test-isolation":       [0.9, "Auto-cleanup, no shared state"],
  "overall-quality":      [0.93, "Production-ready"]
}
EOF

# List available templates
bash .claude/hooks/langfuse-push-score.sh --list-templates
```

Available templates: `test-quality` · `code-review` · `accuracy-efficiency`

## Trace ID convention

```
<safeSession>-init   # session-start trace
<safeSession>-001    # prompt #1
<safeSession>-002    # prompt #2
```

Find trace IDs from session log filenames:

```bash
ls .claude/session-logs/<session-id>/
# prompt-001-xxx.jsonl → traceId = <safeSession>-001
```

## Interrupt handling

When the user presses Escape mid-turn, the hook detects the interrupt marker in the transcript and switches from background flush to `flushSync` — blocking until data is posted to Langfuse before Claude closes.

## Bypass

| Env | Scope |
|-----|-------|
| `SKIP_LANGFUSE=1` | Disable Langfuse push only — session logs still run |
| `SKIP_SCORE_DETECTOR=1` | Disable auto score detection |
| `SKIP_HOOKS=1` | Disable all hooks |
| `LANGFUSE_DEBUG=1` | Enable verbose debug output |
| `LANGFUSE_VERIFY_SCORES=0` | Skip score verification after push |

## Install

```json
{
  "enabledPlugins": {
    "observability@qa-harness-dev": true
  }
}
```

Granular control: set `SKIP_LANGFUSE=1` to keep session logs active without pushing to Langfuse.
