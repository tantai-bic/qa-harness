# qa-context

Injects QA workflow context into every prompt — roadmap reading, skill docs, and test automation orchestration.

## What it does

Three hooks fire on every `UserPromptSubmit`:

| Hook | Event | Action |
|------|-------|--------|
| `enforce-roadmap-reading.sh` | UserPromptSubmit | Injects roadmap doc reminder before implement/test requests if consumer has a roadmap |
| `orchestrate-test-automation.sh` | UserPromptSubmit | 2-mode orchestration: LOGIC mode (writing tests) → full QA checklist; TEXT-ONLY mode (fixing tags/text) → preserves structure without re-running checklist |
| `preload-qa-context.sh` | UserPromptSubmit | Loads `qa-engineer` + `qa-test-case` + `test-quality-checklist` skill docs once per session |

## Roadmap enforcement

If the consumer has a roadmap at `docs/roadmap/`, the hook injects a reminder to read the relevant roadmap doc before implementing features or writing tests. Ensures Claude works aligned to current sprint scope.

## Test orchestration modes

The `orchestrate-test-automation` hook classifies each prompt:

- **LOGIC mode** — prompt involves writing new test logic → injects full Rule #6 split reminder (P0/P1/P2 files), factory pattern, and skill checklist
- **TEXT-ONLY mode** — prompt only touches tags, imports, or text → preserves existing structure, skips re-orchestration

## Preload behavior

`preload-qa-context` loads the three core QA skill docs **once per session** (not on every prompt). Subsequent prompts in the same session skip the load — the content is already in context.

## Bypass

| Env | Scope |
|-----|-------|
| `SKIP_TEST_ORCHESTRATION=1` | Skip test automation orchestration |
| `SKIP_HOOKS=1` | Disable all hooks |

## Install

```json
{
  "enabledPlugins": {
    "qa-context@qa-harness-dev": true
  }
}
```

Requires `bmad-workflows` to be enabled — skill docs are sourced from that plugin.
