# cost-control

Blocks duplicate `Read` calls to avoid wasting cache tokens on files already loaded in context.

## What it does

| Hook | Event | Action |
|------|-------|--------|
| `enforce-read-dedup.sh` | PreToolUse Read | **Block** if the file was already read in the current session without a subsequent Edit/Write |

## Why this matters

Each duplicate Read on a file already in context costs cache_read tokens (~$0.10–0.20 per call). Observed in practice: 23 sequential redundant reads in one turn = ~$15.68. Grouping into 5 parallel batches and deduping = **−60% cost/turn**.

## How it works

The hook tracks which files Claude has read per session. A repeat Read is blocked unless:

- The file was modified by a subsequent `Edit` or `Write` (context is outdated → re-read allowed)
- A `compact` occurred (hook resets counter — compact clears context)
- Edit reports "File has not been read" (auto-allow escape valve for post-compact flows)

## Compact-aware behavior (v2)

After a context compact, the dedup counter resets automatically. Files read before compact are treated as unread — Claude can safely re-read them.

## Bypass

| Env | Scope |
|-----|-------|
| `SKIP_READ_DEDUP=1` | Allow all reads regardless of duplication |
| `SKIP_HOOKS=1` | Disable all hooks |

Use `SKIP_READ_DEDUP=1` when a file has genuinely changed externally (outside Claude's session) and the transcript doesn't reflect the change.

## Install

```json
{
  "enabledPlugins": {
    "cost-control@qa-harness-dev": true
  }
}
```

Low-overhead plugin — safe to enable on any project.
