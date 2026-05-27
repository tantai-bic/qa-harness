# Conventions — Naming, Paths, Change Scenarios, Pre-commit

> Quy ước đặt tên + flow sửa file khi có thay đổi + checklist trước commit.

## Naming + path conventions

| Item           | Convention                                                                                    |
| -------------- | --------------------------------------------------------------------------------------------- |
| File names     | `kebab-case.ts`                                                                               |
| Import         | `@src/*` alias (NOT `../../../src/*`)                                                         |
| Fixture import | `@src/fixtures/<domain>.fixture` (specific) hoặc `@src/fixtures` (merged hub)                 |
| Test path      | `tests/api/{domain}/{story-folder}/P{n}-{feature}.spec.ts`                                    |
| Priority       | `P0` critical, `P1` important, `P2` nice, `P3` perf — **split files theo priority (Rule #6)** |

## Change scenarios — sửa file nào?

| Scenario                          | Files                                                                                                                                          |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| BE đổi base URL                   | `.env` hoặc `src/utils/env-config.ts`                                                                                                          |
| BE đổi endpoint path              | `src/constants/api.constants.ts`                                                                                                               |
| BE thêm endpoint                  | constants + `*.service.ts`                                                                                                                     |
| BE đổi req/resp format            | `*.types.ts` + `*.service.ts`                                                                                                                  |
| FE đổi URL route                  | `src/constants/routes.constants.ts`                                                                                                            |
| FE đổi locator (testid/role/text) | **CHỈ** sửa `*.page.ts` hoặc `*.component.ts` — spec KHÔNG động                                                                                |
| FE refactor component (header...) | `src/components/<x>.component.ts` — mọi page consume tự pickup                                                                                 |
| FE thêm field vào form            | `*.page.ts` (add locator + action) + factory (add field) + types (add prop)                                                                    |
| Thêm wait/format util mới         | `src/helpers/<group>.helper.ts` — KHÔNG nhét vào page/spec                                                                                     |
| Thêm API module                   | 4 files trong `src/<module>/` + endpoints constants                                                                                            |
| Thêm E2E module                   | 6 files trong `src/<module>/` + routes constants + fixture                                                                                     |
| **Test fail vì BE bug**           | **KHÔNG sửa test** — log bug theo [template](../../../docs/templates/log-bug-api-template.md). Hierarchy of Truth: test-design > test code > BE > API-DOC |
| **E2E flaky (intermittent fail)** | KHÔNG retry-loop. Identify root cause: missing wait? race condition fixture? → fix helper/fixture, không sửa spec.                              |

## Pre-commit checklist

**API tests:**
```
☐ Mọi API call qua *.service.ts (NO request.post direct)
☐ Mọi payload qua factory (NO hardcode)
☐ Mọi URL từ API_ENDPOINTS (NO hardcode)
☐ testName param truyền vào service call
☐ Negative test dùng parseErrorResponse + isApiErrorResponse
☐ error.code regex /^ERR_\d+$/ (NOT hardcode)
☐ 401 test: fresh context + *WithoutAuth()
☐ 403 test: dedicated test user login (NOT same context)
```

**E2E tests:**
```
☐ Mọi locator sống trong *.page.ts hoặc *.component.ts (NO raw selector trong spec)
☐ Locator ưu tiên getByRole > getByLabel > getByTestId > CSS
☐ Mọi URL từ ROUTES constant (NO hardcode)
☐ KHÔNG page.waitForTimeout() — dùng Locator.waitFor / expect.toBeVisible
☐ Component reuse ≥ 2 page → tách COM
☐ Page compose component qua field, KHÔNG inherit
☐ Fixture cover setup (API seed + POM init), test chỉ destructure
```

**Universal:**
```
☐ Import dùng @src/* alias (NO ../../src/)
☐ Import test từ @src/fixtures (NOT @playwright/test)
☐ Spec split P0/P1/P2 (Rule #6) — 1 priority = 1 file
☐ Helper pure / declare side-effect rõ trong tên
☐ Layer dependency tuân thủ: tests → fixtures → pages/components → services/helpers → factory/constants/types
☐ npx tsc --noEmit pass
☐ No `any`/`unknown`
```
