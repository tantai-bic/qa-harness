---
name: qa-engineer
description: Code patterns chuẩn cho Playwright + TypeScript automation — full-stack layer architecture (types/constants/factory/service/pages/components/helpers/fixtures), POM + COM cho E2E, Service + Factory cho API, Helper utilities, Fixture composition. Bundled sub-docs cho architecture, patterns-api, patterns-e2e, helpers, module-creation, conventions. Dùng khi viết/refactor service, factory, page object, component object, helper, fixture, hoặc verify code có đúng layer dependency.
---

# QA Engineer — Code Patterns

Skill cung cấp full-stack code patterns cho Playwright + TypeScript QA harness. Pair với [test-case skill](../qa-test-case/SKILL.md) + [test-quality-checklist](../test-quality-checklist/SKILL.md).

## Bundled documents (đọc khi cần)

| Doc | Khi nào đọc |
|-----|-------------|
| [`architecture.md`](./architecture.md) | Tech stack, Playwright config, layer architecture, data flow, env resolution, directory structure |
| [`patterns-api.md`](./patterns-api.md) | Service + Factory + Constants + Fixture + Error Assertion + Security (401/403) |
| [`patterns-e2e.md`](./patterns-e2e.md) | POM + COM + Locator strategy + Composable Fixture (browser tests) |
| [`helpers.md`](./helpers.md) | Helper Pattern (wait/format/assert/network) + Logger format |
| [`module-creation.md`](./module-creation.md) | 4-file API module template + 6-file E2E module template + checklist |
| [`conventions.md`](./conventions.md) | Naming, paths, change scenarios (sửa file nào khi X), pre-commit checklist |

## Quick-pick

| Đang làm gì? | Đọc |
|--------------|-----|
| Viết API test mới | architecture → patterns-api → module-creation |
| Viết E2E test mới | architecture → patterns-e2e → module-creation |
| Refactor service / factory | patterns-api § Service/Factory |
| Thêm page object mới | patterns-e2e § POM |
| Component reuse ≥ 2 page | patterns-e2e § COM |
| Wait/format util duplicate trong test | helpers § extraction |
| Đặt tên file / folder | conventions § Naming |
| BE đổi endpoint / FE đổi locator | conventions § Change scenarios |
| Trước khi commit | conventions § Pre-commit checklist |

## 8 Golden Rules (quick-ref)

1. **Service-only API calls** — KHÔNG `request.post` direct. Mọi call qua `*.service.ts`
2. **Factory-only payloads** — KHÔNG hard-code data. Mọi payload qua `create<Entity>Payload()`
3. **Constants-only URLs** — KHÔNG hardcode. Mọi endpoint từ `API_ENDPOINTS`, mọi route từ `ROUTES`
4. **Alias-only imports** — `@src/*`, KHÔNG `../../src/`
5. **Fixture-only `test`** — `import { test } from '@src/fixtures/...'`, KHÔNG `@playwright/test`
6. **POM-only locators** — locator sống trong `pages/` hoặc `components/`, KHÔNG raw selector trong spec
7. **Priority-split files** — mỗi P0/P1/P2/P3 = 1 file riêng (CI/CD grep)
8. **Type-safe** — KHÔNG `any`/`unknown`. Cast inline interface

## Layer dependency (one-way)

```
tests/ → fixtures/ → pages/ + components/ → services/ + helpers/ → factory/ + constants/ + types/
```

Layer dưới KHÔNG được import layer trên. Detail: [`architecture.md`](./architecture.md) § 5.

## Hierarchy of Truth (universal)

1. Test Design Document (HIGHEST)
2. Test Code (verification)
3. BE response (implementation — có thể bug)
4. API-DOC (documentation — có thể outdated)

Test fail khi follow test-design ≠ test sai → KHÔNG sửa test, log bug.

## References

- [test-case skill](../qa-test-case/SKILL.md) — Test design (happy/bad/edge, BVA, equivalence, decision table)
- [test-quality-checklist](../test-quality-checklist/SKILL.md) — 9 rules + 41 items
- [bug log template](../../docs/templates/log-bug-api-template.md)
