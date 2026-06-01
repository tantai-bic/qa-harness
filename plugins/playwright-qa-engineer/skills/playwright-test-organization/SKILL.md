# Playwright Test Organization — Rules & Patterns

> Canonical reference cho cách tổ chức, viết, và chạy Playwright tests.
> Hook `orchestrate-test-automation.sh` tự động nhắc các rules này khi detect test-writing request.

## Rule #6 — Priority-Based File Split (CRITICAL)

**❌ SAI — gộp nhiều priority vào 1 file:**
```
tests/api/auth/login/auth-login.spec.ts   ← chứa P0 + P1 + P2 lẫn lộn
```

**✅ ĐÚNG — tách file theo priority:**
```
tests/api/{domain}/{story-folder}/
├── P0-{feature}.spec.ts     Critical path — phải pass mọi CI run
├── P1-{feature}.spec.ts     Important — run trong daily/regression
├── P2-{feature}.spec.ts     Nice-to-have — weekly hoặc manual
└── P3-{feature}.spec.ts     Perf/benchmark — riêng pipeline
```

**Tại sao:** CI/CD grep theo `--grep P0` / `--grep P1`. Gộp priority phá vỡ selective execution.

### Priority Definition

| Priority | Khi nào dùng | CI cadence |
|----------|-------------|------------|
| P0 | Happy path, critical business flow, auth security | Mọi commit (block merge) |
| P1 | Error cases, edge cases quan trọng, data validation | Daily / PR |
| P2 | Boundary conditions, soft edge cases | Weekly / regression |
| P3 | Performance, load, benchmark | Riêng pipeline |

### Ví dụ cụ thể

```
tests/api/auth/login/
├── P0-login-success.spec.ts           Happy path + 401 unauthorized
├── P1-login-validation.spec.ts        Input validation, wrong credentials
└── P2-login-edge-cases.spec.ts        Rate limiting, expired token

tests/e2e/dashboard/overview/
├── P0-dashboard-render.spec.ts        Page loads, critical widgets
└── P1-dashboard-interaction.spec.ts   Filters, sorting, pagination
```

---

## Service + Factory Discipline

### Rule: Per-module, không generic

**❌ SAI — generic service:**
```ts
import { ApiService } from '@src/services/api.service';
const res = await ApiService.createResource(payload);
```

**✅ ĐÚNG — module-specific service + factory:**
```ts
import { AuthService } from '@src/services/auth/auth.service';
import { createLoginPayload } from '@src/factories/auth.factory';

const payload = createLoginPayload({ username: 'user@test.com' });
const res = await AuthService.login(testName, payload);
```

### Factory Pattern (parallel-safe)

```ts
// src/factories/auth.factory.ts
export function createLoginPayload(override: Partial<LoginDto> = {}): LoginDto {
  return {
    username: `test_${Date.now()}@example.com`,
    password: 'Test@123',
    ...override,
  };
}
```

**Rules:**
- Mọi payload đi qua factory (KHÔNG hardcode data inline)
- Mọi API call đi qua `*.service.ts` (KHÔNG `request.post()` trực tiếp)
- Truyền `testName` vào mọi service call (traceability trong logs)
- Endpoint từ `API_ENDPOINTS` constant (KHÔNG hardcode URL)
- Import path: `@src/*` alias

### Workflow khi viết test mới

1. Grep `src/{module-path}/` → tìm `{feature}.service.ts` + `{feature}.factory.ts` đã có
2. Nếu thiếu → tạo mới theo Module Creation Pattern (`skills/qa-engineer/SKILL.md § Module Creation`)
3. Import factory cho payload, service cho API call
4. Truyền `testName` string vào service

---

## Hierarchy of Truth

Khi BE response khác với test expectation:

```
1. test-design / qa-test-case doc  ← HIGHEST (requirement)
2. Test code                       ← verification artifact
3. BE response                     ← implementation (có thể bug)
4. API-DOC.md                      ← documentation (có thể outdated)
```

**Test FAIL ≠ test sai.** KHÔNG sửa test để pass khi BE sai.
→ Log bug theo template `docs/templates/log-bug-api-template.md`.

---

## Error Assertion Contract

```ts
import { parseErrorResponse, isApiErrorResponse, getApiErrorCode } from '@src/utils/error-handler';

// ✅ ĐÚNG — typed, regex-based
const error = await parseErrorResponse(response);
expect(isApiErrorResponse(error)).toBe(true);
expect(error.error.code).toMatch(/^ERR_\d+$/);
expect(error.meta.requestId).toBeDefined();

// ❌ SAI — hardcoded code (BE có thể đổi)
expect(error.error.code).toBe('ERR_4021');
```

**401/403 tests — auth isolation:**
```ts
// Fresh browser context per test (không leak auth state)
test('401 unauthorized', async ({ browser }) => {
  const ctx = await browser.newContext(); // fresh — no cookies/storage
  const page = await ctx.newPage();
  // ... test without auth
  await ctx.close();
});

// Hoặc dùng helper:
const res = await AuthService.getProfileWithoutAuth(testName);
expect(res.status()).toBe(401);
```

---

## Execute-Before-Complete (Rule #10)

**BẮTT BUỘC** sau mỗi Write/Edit `*.spec.ts`:

```bash
# Detect framework từ package.json
# @playwright/test → npx playwright test <file>
# jest → npx jest <file>
# vitest → npx vitest run <file>

# Chạy scope hẹp — chỉ file vừa viết, KHÔNG full suite
npx playwright test tests/api/auth/login/P0-login-success.spec.ts
```

**Report với evidence:**
```
8 pass, 1 fixme (ERR_4021 BE bug logged), 0 fail
```

KHÔNG báo "hoàn thành" khi chưa chạy test. Hook `run-test-mark-fixme.sh` auto-fire nhưng Claude vẫn phải verify + summarize.

**Classify kết quả:**
| Kết quả | Action |
|---------|--------|
| pass | ✓ Mark task done |
| fail (BE bug) | Log bug, mark test `.fixme()` với note |
| fail (test logic) | Fix test trước khi mark done |
| error (setup) | Fix import/factory trước khi mark done |

---

## Scope Discipline

- **Mặc định:** 1 module/feature per task — KHÔNG drift sang module khác
- User nói "cả phase" / "all modules" → mới làm nhiều module
- Module hint detection: từ `tests/{layer}/{domain}` path hoặc keyword trong prompt

---

## Output Terseness (cost optimization)

**❌ Tránh — thinking out loud:**
```
"Đã đọc đủ 3 technique docs. Áp dụng: Boundary → P0(0)..."
"P2 thiếu parseErrorResponse... Sửa ngay"
"Thư mục trống, sẵn sàng viết 3 file. Viết P0, P1, P2 song song."
```

**✅ Pattern đúng — action first, ≤50 tokens:**
```
"Đọc service signature." → Read tool
"Viết 3 file P0/P1/P2." → Write tools (parallel)
"Fix parseErr cho P2." → Edit tool
```

**Parallel tool calls (CRITICAL):**
Mọi Read/Grep/Write **độc lập** gom vào 1 message. 23 sequential calls = $15.68/turn → 5 parallel batches = -60% cost.
