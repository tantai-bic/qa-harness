# Playwright Setup — Project Structure & Toolchain

> Reference doc cho consumer setup Playwright project đúng convention.
> Hook `check-playwright-setup.sh` tự động validate các mục này khi session startup.

## 1. Required Project Structure

```
consumer-project/
├── package.json                   NPM manifest (Playwright + TS + linting deps)
├── playwright.config.ts           Playwright config (timeouts, projects, retries)
│   (hoặc playwright.config.js)
├── tests/
│   ├── api/                       API/backend test specs
│   │   └── {domain}/
│   │       └── {story-folder}/
│   │           ├── P0-{feature}.spec.ts
│   │           ├── P1-{feature}.spec.ts
│   │           └── P2-{feature}.spec.ts
│   └── e2e/                       End-to-end test specs
│       └── {domain}/
│           └── {story-folder}/
│               └── P{n}-{feature}.spec.ts
├── src/
│   ├── constants/                 API_ENDPOINTS, shared constants
│   ├── fixtures/                  Playwright fixture extensions
│   ├── pages/                     Page Object Models (E2E)
│   ├── components/                Reusable page components
│   ├── helpers/                   Shared test helpers / utils
│   └── factories/                 Payload factories (per-module)
└── docs/
    └── roadmap/                   Feature state machine docs (consumer-defined)
```

## 2. Required Packages

Declared trong `package.json` (`dependencies` hoặc `devDependencies`):

| Package | Vai trò | Install |
|---------|---------|---------|
| `@playwright/test` | Test framework + runner | `npm i -D @playwright/test && npx playwright install` |
| `lint-staged` | Format-on-commit gate | `npm i -D lint-staged` |
| `eslint` | Linter | `npm i -D eslint` |
| `prettier` | Formatter | `npm i -D prettier` |

> Detection strategy: check **declared** (deps/devDeps), KHÔNG stat `node_modules`.
> Safe cho Yarn PnP và pnpm `shamefully-hoist=false`.

## 3. playwright.config.ts Conventions

```ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 30_000,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 4 : undefined,
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    extraHTTPHeaders: {
      'Accept': 'application/json',
    },
  },
  projects: [
    { name: 'api',  testMatch: /tests\/api\/.+\.spec\.ts/ },
    { name: 'e2e',  testMatch: /tests\/e2e\/.+\.spec\.ts/, use: { ...devices['Desktop Chrome'] } },
  ],
});
```

## 4. Capability Degradation

| Missing | Consequence |
|---------|-------------|
| `package.json` | Cannot detect test framework |
| `playwright.config.ts` | `run-test-mark-fixme.sh` cannot find config |
| `tests/` | No location for test specs |
| `@playwright/test` | Playwright runner unavailable |
| `lint-staged` | Format-on-commit gate broken |
| `eslint` / `prettier` | Code quality enforcement off |

## 5. Bypass & Customization

```bash
# Bypass setup check for this session
SKIP_PLAYWRIGHT_SETUP=1 claude

# Add extra required paths (newline-separated)
CONSUMER_REQUIRED_PATHS=$'docs/api/\ntsconfig.json' claude

# Skip default paths (only check CONSUMER_REQUIRED_PATHS)
CONSUMER_SETUP_SKIP_DEFAULTS=1 claude

# Master bypass (all hooks)
SKIP_HOOKS=1 claude
```

## 6. Plugin-specific Setup (Other Plugins)

| Plugin | Additional requirements |
|--------|------------------------|
| `bmad-workflows` | `_bmad/bmm/config.yaml`, `docs/roadmap/`, `docs/templates/` |
| `test-enforcement` | `src/fixtures/`, `src/pages/`, `src/helpers/`, `src/factories/`, `src/constants/` |
