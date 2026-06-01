# playwright plugin

Playwright setup validation + test automation orchestration for Claude Code QA workflows.

## Hooks

| Event | Script | Action |
|-------|--------|--------|
| `SessionStart` (startup) | `check-playwright-setup.sh` | Validates Playwright project structure + required packages on cold start |
| `UserPromptSubmit` | `orchestrate-test-automation.sh` | Injects test-writing checklist (Rule #6 split, service/factory discipline, hierarchy of truth) |
| `UserPromptSubmit` | `preload-playwright-context.sh` | Preloads QA skill docs from bmad-workflows (1× per session cache, ~6K tokens) |

## Setup check (`check-playwright-setup.sh`)

Fires on `startup` only — silent if everything passes.

**Required paths:**

| Path | Purpose |
|------|---------|
| `package.json` | NPM manifest |
| `playwright.config.ts` \| `playwright.config.js` | Playwright config (timeouts, projects, retries) |
| `tests/` | Test directory (`tests/api/`, `tests/e2e/`) |

**Required packages** (declared in `package.json` deps/devDeps):

| Package | Purpose |
|---------|---------|
| `@playwright/test` | Playwright test framework |
| `lint-staged` | Format-on-commit gate |
| `eslint` | Linter |
| `prettier` | Formatter |

Detection: checks declared in `package.json`, NOT `node_modules` — safe for Yarn PnP and pnpm.

**Customize:**
```bash
# Add extra paths
CONSUMER_REQUIRED_PATHS=$'docs/api/\ntsconfig.json' claude

# Skip defaults
CONSUMER_SETUP_SKIP_DEFAULTS=1 claude

# Bypass per-session
SKIP_PLAYWRIGHT_SETUP=1 claude
```

## Test orchestration (`orchestrate-test-automation.sh`)

Triggers on: `viết test`, `write test`, `create test`, `spec.ts`, `tests/api`, `tests/e2e`, and related patterns.

**Two modes:**
- **LOGIC** (new test code) → injects full orchestration checklist (scope discipline, Rule #6, service/factory, hierarchy of truth, execute-before-complete)
- **TEXT-ONLY** (rename/fix text) → minimal reminder, skips skill doc loading

**Key enforcements:**
- Rule #6: split test files by priority (`P0-*.spec.ts` / `P1-*.spec.ts` / `P2-*.spec.ts`)
- All payloads via factory (parallel safety)
- All API calls via `*.service.ts` — no direct `request.post()`
- Execute test before marking complete (`npx playwright test <file>`)

## Context preload (`preload-playwright-context.sh`)

On first test-writing trigger per session: injects full content of 3 skill docs from `bmad-workflows` plugin:
- `skills/qa-engineer/SKILL.md` — code patterns
- `skills/qa-test-case/SKILL.md` — test design index
- `skills/test-quality-checklist/SKILL.md` — 9 quality rules (head only)

On subsequent triggers: short reminder only (~50 tokens). Requires `bmad-workflows` plugin installed.

## Bypass env vars

| Var | Scope |
|-----|-------|
| `SKIP_PLAYWRIGHT_SETUP=1` | Skip setup check hook |
| `SKIP_SETUP_CHECK=1` | Legacy alias for setup check |
| `SKIP_TEST_ORCHESTRATION=1` | Skip orchestration hook |
| `SKIP_PLAYWRIGHT_PRELOAD=1` | Skip preload hook |
| `SKIP_QA_PRELOAD=1` | Legacy alias for preload |
| `SKIP_HOOKS=1` | Master bypass (all hooks) |

## Install

```json
// ~/.claude/settings.json
{
  "enabledPlugins": {
    "playwright@qa-harness": true
  }
}
```

Recommended: also enable `bmad-workflows` (for skills), `test-enforcement` (for quality gates), and `observability` (for session logging).
