# Playwright Setup — Core Project Structure & Toolchain

> Reference doc cho consumer setup Playwright project từ zero — chỉ scope **core setup**.
> Hook `check-playwright-setup.sh` tự động validate các mục này khi session startup.
>
> ❌ Skill này KHÔNG cover cách viết test (naming convention, P0/P1/P2 split, …) —
> xem `skills/playwright-test-organization/SKILL.md` cho test writing.

## 1. Minimum Required Files & Folders

Đây là điều kiện CẦN để Playwright runner + Git hooks hoạt động:

```
consumer-project/
├── package.json                   NPM manifest
├── playwright.config.ts           Playwright config (hoặc .js)
├── tests/                         Test root directory
└── .husky/
    └── pre-commit                 Git pre-commit hook (chạy lint-staged)
```

Setup check pass khi 5 mục trên tồn tại. Cấu trúc bên trong `tests/` (api / e2e, naming
convention, priority split) là phạm vi của test-organization, KHÔNG enforce ở đây.

## 2. Required Packages

Declared trong `package.json` (`dependencies` hoặc `devDependencies`):

| Package | Vai trò | Install |
|---------|---------|---------|
| `@playwright/test` | Test framework + runner | `npm i -D @playwright/test && npx playwright install` |
| `husky` | Git hooks manager | `npm i -D husky && npx husky init` |
| `lint-staged` | Format-on-commit gate (chạy từ husky pre-commit) | `npm i -D lint-staged` |
| `eslint` | Linter | `npm i -D eslint` |
| `prettier` | Formatter | `npm i -D prettier` |

> Detection strategy: check **declared** (deps/devDeps), KHÔNG stat `node_modules`.
> Safe cho Yarn PnP và pnpm `shamefully-hoist=false`.

## 3. playwright.config.ts — Minimal Working Config

```ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  timeout: 30_000,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 4 : undefined,
  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
  },
});
```

Config này đủ chạy. Mở rộng projects/devices/reporters tuỳ nhu cầu — không phải core setup.

## 4. Husky Setup (Git pre-commit hook)

`npx husky init` tạo:
- `.husky/pre-commit` (default: chạy `npm test`)
- Thêm `"prepare": "husky"` vào `package.json` scripts (auto-install hooks khi `npm install`)

**Sửa `.husky/pre-commit` để chạy lint-staged:**

```sh
#!/bin/sh
npx lint-staged
```

**Thêm lint-staged config vào `package.json`:**

```json
{
  "scripts": {
    "prepare": "husky"
  },
  "lint-staged": {
    "*.{ts,tsx,js,jsx}": ["eslint --fix", "prettier --write"],
    "*.{json,md}": ["prettier --write"]
  }
}
```

Verify: `git add . && git commit -m "test"` → husky phải fire `lint-staged`.

## 5. Bootstrap Commands (từ zero)

```bash
# 1. Khởi tạo project + Playwright
npm init -y
npm i -D @playwright/test
npx playwright install

# 2. Linting + formatter toolchain
npm i -D eslint prettier lint-staged

# 3. Husky (Git pre-commit hook)
npm i -D husky
npx husky init                       # tạo .husky/ + .husky/pre-commit + script prepare

# 4. Edit .husky/pre-commit để chạy lint-staged thay vì `npm test`
echo 'npx lint-staged' > .husky/pre-commit

# 5. Xác nhận structure
ls package.json playwright.config.ts tests/ .husky/pre-commit
```

Sau bước này, restart Claude session → `check-playwright-setup.sh` silent (pass).

## 6. Capability Degradation

| Missing | Hậu quả |
|---------|---------|
| `package.json` | Không detect được test framework |
| `playwright.config.ts` | `run-test-mark-fixme.sh` không tìm được config |
| `tests/` | Không có nơi chứa test specs |
| `@playwright/test` | Playwright runner unavailable |
| `.husky/` + `.husky/pre-commit` | Git pre-commit hook KHÔNG fire — lint/test bypass |
| `husky` package | `npm install` không tự install Git hooks |
| `lint-staged` | Format-on-commit gate hỏng |
| `eslint` / `prettier` | Code quality enforcement off |

## 7. Bypass & Customization

```bash
# Bypass setup check (per-session)
SKIP_PLAYWRIGHT_SETUP=1 claude

# Add extra required paths (newline-separated)
CONSUMER_REQUIRED_PATHS=$'docs/api/\ntsconfig.json' claude

# Skip default paths (only check CONSUMER_REQUIRED_PATHS)
CONSUMER_SETUP_SKIP_DEFAULTS=1 claude

# Master bypass (all hooks)
SKIP_HOOKS=1 claude
```

## 8. Plugin-specific Setup (Other Plugins)

Mỗi plugin trong marketplace có setup check riêng. Liệt kê ở đây để consumer biết
tổng thể, KHÔNG enforce ở skill này:

| Plugin | Additional requirements |
|--------|------------------------|
| `bmad-workflows` | `_bmad/bmm/config.yaml`, `docs/roadmap/`, `docs/templates/` |
| `test-enforcement` | `src/fixtures/`, `src/pages/`, `src/helpers/`, `src/factories/`, `src/constants/` |
| `observability` | `LANGFUSE_PUBLIC_KEY` + `LANGFUSE_SECRET_KEY` in env |

## 9. Next Steps Sau Khi Setup

Sau khi 5 core files/folders + 5 packages đã có → setup CORE đã xong.

Để bắt đầu viết test:
- Đọc `skills/playwright-test-organization/SKILL.md` (Rule #6, service/factory, hierarchy)
- Đọc `skills/playwright-qa-workflow/SKILL.md` (roadmap workflow, scope discipline)
- Setup `src/` structure đúng convention (xem `test-enforcement` plugin requirements)
