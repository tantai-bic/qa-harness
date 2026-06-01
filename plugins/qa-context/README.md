# qa-context plugin

Roadmap reading enforcement for Claude Code QA workflows.

> **Note:** Test automation orchestration and QA skill doc preloading have been moved to the `playwright` plugin.

## Hooks

| Event | Script | Action |
|-------|--------|--------|
| `UserPromptSubmit` | `enforce-roadmap-reading.sh` | Injects reminder to read roadmap docs before implementing features or writing tests |

## Roadmap enforcement (`enforce-roadmap-reading.sh`)

Triggers when user asks to implement or test a feature. Detects keywords:
- **VN:** `tính năng`, `viết test`, `implement`, `thực hiện`, `làm tính năng`
- **EN:** `implement`, `write test`, `create feature`, `build feature`

When triggered:
1. Discovers `docs/roadmap/` in consumer project
2. Injects reminder to read the relevant roadmap file(s) recursively (upstream → downstream chain)
3. Supports custom trigger patterns via `ROADMAP_TRIGGER_REGEX` env var

Consumer's roadmap structure: `docs/roadmap/README.md` (index) → story/feature docs.

## Bypass

| Var | Scope |
|-----|-------|
| `SKIP_ROADMAP_READING=1` | Skip roadmap enforcement |
| `SKIP_HOOKS=1` | Master bypass (all hooks) |

## Install

```json
// ~/.claude/settings.json
{
  "enabledPlugins": {
    "qa-context@qa-harness": true
  }
}
```

Recommended: also enable `playwright` plugin for test orchestration + skill doc preloading.
