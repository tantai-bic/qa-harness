# playwright-qa-engineer plugin

All-in-one Playwright QA plugin: setup validation, roadmap enforcement, test orchestration, and skill doc preloading. Merges the `playwright` and `qa-context` plugins into a single cohesive unit with 3 built-in skill references.

## Hooks

| Event | Script | Action |
|-------|--------|--------|
| `SessionStart` (startup) | `check-playwright-setup.sh` | Validates Playwright project structure + required packages |
| `UserPromptSubmit` | `enforce-roadmap-reading.sh` | Injects reminder to read roadmap docs before implementing |
| `UserPromptSubmit` | `orchestrate-test-automation.sh` | Injects test-writing checklist (Rule #6, service/factory, hierarchy) |
| `UserPromptSubmit` | `preload-playwright-context.sh` | Preloads 3 local skill docs (1× per session cache) |
| `UserPromptSubmit` | `inject-dev-playwright-menu.sh` | Injects `[PS] Setup Playwright` menu item khi user activate BMAD dev agent |

## Skills

Extracted from hook content into standalone reference docs:

| Skill | Content |
|-------|---------|
| `skills/playwright-setup/SKILL.md` | Required project structure, packages, playwright.config conventions |
| `skills/playwright-test-organization/SKILL.md` | Rule #6 (P0/P1/P2 split), service/factory, hierarchy of truth, error assertion, Rule #10 |
| `skills/playwright-qa-workflow/SKILL.md` | Roadmap reading workflow, scope discipline, QA decision framework, CICD tags |

Skills are preloaded automatically on test-writing triggers. Also readable on demand.

## Setup check

Validates on `startup`:

| Path | Purpose |
|------|---------|
| `package.json` | NPM manifest |
| `playwright.config.ts` \| `playwright.config.js` | Playwright config |
| `tests/` | Test directory |

| Package | Purpose |
|---------|---------|
| `@playwright/test` | Playwright test framework |
| `lint-staged` | Format-on-commit |
| `eslint` | Linter |
| `prettier` | Formatter |

## Roadmap enforcement

Triggers when user asks to implement or test. Requires consumer to have `docs/roadmap/` set up. Recursively injects upstream reading reminder.

## Test orchestration

Two modes:
- **LOGIC** (new test code) → full checklist from `playwright-test-organization` skill
- **TEXT-ONLY** (rename/fix text) → minimal reminder, keeps tags + structure

## Context preload

On first test-writing trigger per session: loads 3 local skills + `test-quality-checklist` head from bmad-workflows. Subsequent triggers: short reminder only.

## Bypass env vars

| Var | Scope |
|-----|-------|
| `SKIP_PLAYWRIGHT_SETUP=1` | Skip setup check |
| `SKIP_ROADMAP_READING=1` | Skip roadmap enforcement |
| `SKIP_TEST_ORCHESTRATION=1` | Skip orchestration |
| `SKIP_PLAYWRIGHT_PRELOAD=1` | Skip preload |
| `SKIP_DEV_PLAYWRIGHT_MENU=1` | Skip BMAD dev menu extension |
| `SKIP_HOOKS=1` | Master bypass |
| `ROADMAP_TRIGGER_REGEX=<pattern>` | Custom roadmap trigger |
| `MODULE_KEYWORDS=<space-sep>` | Custom module keywords |

## Install

```json
// ~/.claude/settings.json
{
  "enabledPlugins": {
    "playwright-qa-engineer@qa-harness": true
  }
}
```

Recommended: also enable `bmad-workflows` (for full BMAD agents + skills), `test-enforcement` (pre-write quality gates), and `observability` (session logging).
