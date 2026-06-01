# consumer-setup

SessionStart check that nudges consumers to create required project structure before starting work.

## What it does

| Hook | Event | Action |
|------|-------|--------|
| `check-consumer-setup.sh` | SessionStart (startup only) | Lists missing required paths and packages at session start |

The hook runs once when Claude starts a new session (`startup` matcher — not on resume/clear/compact). It checks for required files, folders, and npm packages, then prints a consolidated warning for anything missing.

## Default checks

**Directory/file structure:**

| Path | Purpose |
|------|---------|
| `_bmad/bmm/config.yaml` | BMAD config — `project_name`, `user_name`, `communication_language` |
| `docs/roadmap/README.md` | Roadmap index for `enforce-roadmap-reading` hook |
| `docs/templates/log-bug-api-template.md` | Bug log template (hierarchy of truth) |
| `playwright.config.ts` / `playwright.config.js` | Playwright config |
| `src/constants/api.constants.ts` | API endpoint constants |
| `src/fixtures/` | Playwright fixtures dir |
| `src/pages/` or `src/page-objects/` or `tests/pages/` | Page Object Model |
| `src/components/` or `src/component-objects/` | Component Object Model |
| `src/helpers/` or `src/utils/` | Helper functions |
| `src/factories/` or `src/data-factories/` | Data factories |
| `tests/` | Test directory |

**npm packages:**

| Package | Purpose |
|---------|---------|
| `playwright` / `@playwright/test` | Test runner |
| `lint-staged` | Commit-time formatting |
| `eslint` | Code quality |
| `prettier` | Code formatting |

## Customization

Add extra required paths via env (newline-separated):

```bash
export CONSUMER_REQUIRED_PATHS="src/custom-dir
docs/custom-doc.md"
```

Skip default checks and use only custom paths:

```bash
export CONSUMER_SETUP_SKIP_DEFAULTS=1
```

## Auto-skip behavior

The hook automatically skips itself when running on the plugin source repo (detected by presence of `.claude-plugin/marketplace.json`). Prevents false positives during plugin development.

## Bypass

| Env | Scope |
|-----|-------|
| `SKIP_SETUP_CHECK=1` | Skip the startup check entirely |
| `SKIP_HOOKS=1` | Disable all hooks |

## Install

```json
{
  "enabledPlugins": {
    "consumer-setup@qa-harness-dev": true
  }
}
```

Safe to enable on any consumer project. Runs only at session startup — zero overhead during normal work.
