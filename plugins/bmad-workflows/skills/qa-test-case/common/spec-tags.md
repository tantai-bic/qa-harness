# Spec Tags — CICD Selective Execution

> Tag taxonomy chuẩn cho mọi test spec để CICD chạy selective (`--grep '@P0'` / `--grep '@Smoke'`). Tag được enforce bởi `enforce-spec-tags.sh` hook.

---

## 3 categories bắt buộc per test/describe

| Category | Required | Tags | Source of truth |
|---|---|---|---|
| **PRIORITY** | 1 tag | `@P0` `@P1` `@P2` `@P3` | File name (`P0-{feature}.spec.ts` → bắt buộc `@P0`) |
| **LAYER** | 1 tag | `@BE` `@FE` | Path (`tests/api/` → `@BE`, `tests/e2e/` → `@FE`) |
| **TYPE** | ≥1 tag | `@Smoke` `@Sanity` `@Regression` `@Function` `@UI` `@UX` | Test intent (developer chọn) |

### PRIORITY semantics

| Tag | Khi nào dùng | CICD slot | Block release? |
|---|---|---|---|
| `@P0` | Critical path — login, checkout, payment | Pre-merge gate, smoke run mỗi PR | ✅ Có |
| `@P1` | Important — search, filter, profile edit | Nightly run | ✅ Có |
| `@P2` | Nice-to-have — preferences, theme, dashboards | Weekly run | ❌ Không (warn) |
| `@P3` | Perf / benchmark — load test, stress test, mem profile | On-demand | ❌ Không (track trend) |

### LAYER semantics

| Tag | Layer | Test runner | Tốc độ |
|---|---|---|---|
| `@BE` | Backend / API contract | Playwright API request mode (no browser) | Nhanh (~100ms/test) |
| `@FE` | Frontend / E2E user flow | Playwright với browser | Chậm (~5-30s/test) |

→ KHÔNG mix `@BE` + `@FE` trong 1 test (1 layer per spec). Nếu cần test full-stack: viết 2 spec riêng, link qua test-design.

### TYPE semantics

| Tag | Định nghĩa | Ví dụ |
|---|---|---|
| `@Smoke` | Subset minimal — verify app bootable + critical paths work | Login OK, homepage load, search return result |
| `@Sanity` | Sau hotfix / config change — verify không break basics | Sau deploy: login + 1 P0 endpoint mỗi domain |
| `@Regression` | Re-run sau code change — catch broken behaviour | Full suite mỗi PR merge to main |
| `@Function` | Functional correctness — đúng requirement | Form validation, business rules, state transitions |
| `@UI` | Visual / interaction layer | Button click, modal open, form layout |
| `@UX` | User experience flow — multi-step journey | Onboarding flow, multi-step form, undo/redo |

→ 1 test có thể nhiều `TYPE` tags. Vd `@Smoke + @Function` (smoke check của function correctness).

---

## Syntax (Playwright v1.42+)

### ✅ Modern syntax (recommended)

```ts
import { test, expect } from "@playwright/test";

test.describe("Login", { tag: "@BE" }, () => {
  test(
    "valid credentials → 200 + token",
    { tag: ["@P0", "@Smoke", "@Function"] },
    async ({ request }) => {
      // ...
    }
  );

  test(
    "invalid password → 401",
    { tag: ["@P0", "@Function"] },
    async ({ request }) => {
      // ...
    }
  );
});
```

### ⚠ Legacy syntax (title-tag — works but ít readable)

```ts
test("login valid @P0 @BE @Smoke", async ({ request }) => {
  // ...
});
```

→ Avoid khi viết test mới — modern syntax dễ parse + tooling support tốt hơn.

---

## CICD usage (`--grep` filter)

| Pipeline | Command | Selection |
|---|---|---|
| Pre-merge gate | `npx playwright test --grep '@P0'` | All P0 tests |
| Smoke check (post-deploy) | `npx playwright test --grep '@Smoke'` | Smoke subset |
| BE regression nightly | `npx playwright test --grep '@BE.*@Regression'` | BE regression only |
| FE smoke per PR | `npx playwright test --grep '@FE.*@Smoke'` | FE smoke only |
| Critical path | `npx playwright test --grep '@P0\|@P1'` | P0 + P1 union |
| Skip slow tests | `npx playwright test --grep-invert '@P3'` | Exclude perf |
| Full regression | `npx playwright test --grep '@Regression'` | All regression |

---

## Auto-validate (hook `enforce-spec-tags.sh`)

Hook BLOCK Write/Edit nếu spec thiếu/sai tag:

| Vi phạm | Hook response |
|---|---|
| Thiếu `@P0` trong `P0-*.spec.ts` | Block — "Thiếu priority tag @P0 (suy ra từ file name)" |
| File `P0-*.spec.ts` chứa `@P1` | Block — "Conflict priority: file là @P0 nhưng spec dùng @P1" |
| Spec ở `tests/api/` không có `@BE` | Block — "Thiếu layer tag @BE (suy ra từ path)" |
| Spec ở `tests/api/` chứa `@FE` | Block — "Conflict layer — di chuyển file sang tests/e2e/" |
| Không có ≥1 type tag (@Smoke/@Sanity/...) | Block — "Thiếu type tag" |
| Tag chỉ trong comment (không gắn test()) | Block — "Tag tồn tại nhưng KHÔNG gắn vào test()/describe()" |

Bypass khi cần (vd rapid prototyping): `SKIP_SPEC_TAGS=1`.

---

## Anti-patterns

❌ **Mix priority trong 1 file** (vi phạm Rule #6 của `test-quality-checklist`):
```ts
// P0-login.spec.ts
test("valid login", { tag: ["@P0", ...] }, ...)
test("password too short", { tag: ["@P1", ...] }, ...)  // ← SAI, tách sang P1-login-validation.spec.ts
```

❌ **Mix layer trong 1 spec**:
```ts
// tests/api/login/P0-login.spec.ts
test("login API", { tag: ["@P0", "@BE", ...] }, ...)
test("login UI form", { tag: ["@P0", "@FE", ...] }, ...)  // ← SAI, tách sang tests/e2e/
```

❌ **Tag chỉ ở comment hoặc title nhưng quên gắn vào test()**:
```ts
// @P0 @BE @Smoke   ← hook không detect được
test("login", async () => { ... });
```

✅ Phải gắn vào `test()` option object:
```ts
test("login", { tag: ["@P0", "@BE", "@Smoke"] }, async () => { ... });
```

❌ **Tag không nằm trong taxonomy** (vd `@critical`, `@important`):
```ts
test("login", { tag: ["@critical", "@BE"] }, ...)  // ← KHÔNG match grep CICD
```

→ Dùng đúng taxonomy: `@critical` → `@P0`, `@important` → `@P1`.

---

## Tag thêm (consumer-specific, optional)

Consumer có thể thêm tag riêng (`@auth`, `@payment`, `@nightly`, `@flaky`,...) NHƯNG **PHẢI giữ đủ 3 category bắt buộc trên trước**. Vd:

```ts
test("checkout flow", { tag: ["@P0", "@FE", "@Smoke", "@payment", "@flaky"] }, ...)
```

CICD có thể filter:
```bash
# Skip flaky tests in pre-merge
npx playwright test --grep '@P0' --grep-invert '@flaky'
```

---

## References

- [`test-quality-checklist/SKILL.md`](../../test-quality-checklist/SKILL.md) § Rule #6 — split priority
- `hooks/enforce-spec-tags.sh` — validation source
- Playwright docs: [Tag tests](https://playwright.dev/docs/test-annotations#tag-tests)
