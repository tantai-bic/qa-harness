# test-enforcement

Pre-write quality gates for Playwright + TypeScript test specs. Blocks Claude from writing non-compliant test code before it hits the file system.

## What it does

Five hooks fire on every `Write` or `Edit` to a test file:

| Hook | Event | Action |
|------|-------|--------|
| `enforce-fixture-helper-prerequisite.sh` | PreToolUse Write\|Edit | **Block** if spec imports a service/factory/fixture/helper that doesn't exist yet |
| `enforce-spec-tags.sh` | PreToolUse Write\|Edit | **Block** if spec is missing required CICD tags |
| `enforce-security-test-presence.sh` | PreToolUse Write\|Edit | **Warn** (non-blocking) when spec tests user input but lacks security coverage |
| `enforce-test-quality-checklist.sh` | PreToolUse Write\|Edit | **Block** if spec violates any of the 9 quality rules |
| `run-test-mark-fixme.sh` | PostToolUse Write\|Edit (async) | After write, runs `npx playwright test <file>` and marks failing tests `test.fixme()` |

## Required CICD tags

Every spec must include all three tag categories:

```typescript
test('description @P1 @BE @Smoke', async () => { ... })
```

| Category | Valid values |
|----------|-------------|
| Priority | `@P0` `@P1` `@P2` `@P3` |
| Layer | `@BE` `@FE` |
| Type | `@Smoke` `@Sanity` `@Regression` `@Integration` `@E2E` |

## 9 Quality rules (enforced by checklist hook)

1. No `any` / `unknown` type casts
2. No hardcoded URLs — use `API_ENDPOINTS` constants
3. All payloads through factory functions (`create<Module>Payload()`)
4. All API calls through `*.service.ts` — no `request.post` directly
5. Pass `testName` to every service call
6. Each priority level in its own file (`P0-feature.spec.ts`, `P1-feature.spec.ts`)
7. Import from `@src/*` alias — no relative `../../` paths
8. Error assertions use `parseErrorResponse` / `getApiErrorCode` — no hardcoded error codes
9. 401/403 tests use fresh context + `*WithoutAuth()` or dedicated test user

## Run-then-fixme behavior

After every `Write`/`Edit` to `tests/**/*.spec.ts`, the async hook:

1. Detects test framework from `package.json` (`@playwright/test` → `npx playwright test`)
2. Runs the modified file
3. Marks failing tests with `test.fixme()` automatically
4. Timeout: 120 seconds

Claude must verify results and summarize with evidence: `N pass / M fixme / K fail`.

## Bypass

| Env | Scope |
|-----|-------|
| `SKIP_FIXTURE_PREREQ=1` | Skip import existence check |
| `SKIP_SPEC_TAGS=1` | Skip CICD tag validation |
| `SKIP_SECURITY_REMINDER=1` | Skip security coverage warning |
| `SKIP_TEST_QUALITY=1` | Skip 9-rule checklist |
| `SKIP_RUN_TEST=1` | Skip post-write test run |
| `SKIP_HOOKS=1` | Disable all hooks |

## Install

```json
{
  "enabledPlugins": {
    "test-enforcement@qa-harness-dev": true
  }
}
```

Pair with `bmad-workflows` for full QA standards context.
