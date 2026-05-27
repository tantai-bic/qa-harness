# QA Engineer — Code Patterns

> Distilled từ [PROJECT-STRUCTURE.md](../PROJECT-STRUCTURE.md). Pair với [test-case skill](../qa-test-case/skill.md) + [TEST-QUALITY-CHECKLIST](../TEST-QUALITY-CHECKLIST.md).

## Layer architecture

| Layer       | Vai trò                                    |
| ----------- | ------------------------------------------ |
| `types`     | Interface shape data                       |
| `factory`   | Faker-based unique payload (parallel-safe) |
| `service`   | API wrapper + logging + verification       |
| `constants` | `API_ENDPOINTS` tập trung                  |
| `fixtures`  | Auto setup/cleanup                         |

Dependency: `tests/ → src/` (one-way, ESLint enforced).

## 3 Core Patterns

### Service Pattern (mandatory)

```typescript
// ❌ Direct API call
await request.post('https://api.sproux.ai/auth/signup', { data });

// ✅ Service wrapper
const { response, payload } = await SignupService.signupWithValidData(request, undefined, testName);
```

Service signature:

```typescript
export async function createX(
    request: APIRequestContext,
    accessToken: string,
    overrides?: Partial<XPayload>,
    testName?: string
): Promise<{ response: APIResponse; payload: XPayload }> {
    const payload = createXPayload(overrides);
    const url = API_ENDPOINTS.X.CREATE;
    if (testName) logger.info(`🧪 ${testName}`);
    logger.info(`   [POST] ${url}`);
    const response = await request.post(url, { data: payload, headers: { Authorization: `Bearer ${accessToken}` } });
    return { response, payload };
}
```

### Factory Pattern (mandatory)

```typescript
// ❌ Hardcoded — collision khi parallel/retry
const payload = { email: 'test@test.com', password: 'Test123!' };

// ✅ Faker-based unique
const payload = createSignupPayload(); // email: test_<ts>_<rand>@example.com
```

Factory signature:

```typescript
export function createXPayload(overrides: Partial<XPayload> = {}): XPayload {
    return {
        email: `test_${Date.now()}_${faker.string.alphanumeric(6)}@example.com`.toLowerCase(),
        password: generateValidPassword(), // 8-15 chars + upper/lower/num/special
        ...overrides,
    };
}
```

### Endpoint Constants (mandatory)

```typescript
// ❌ Hardcoded
await request.post('https://api.sproux.ai/refinements/start');

// ✅ From constants
import { API_ENDPOINTS } from '@src/constants/api.constants';
await request.post(API_ENDPOINTS.REFINEMENT.START);
await request.post(API_ENDPOINTS.REFINEMENT.RESPOND(sessionId));
```

Definition shape:

```typescript
export const API_ENDPOINTS = {
    AUTH: { LOGIN, SIGNUP, LOGOUT },
    REFINEMENT: { START, RESPOND: (id) => `...`, GET: (id) => `...` },
    // ... 30+ domain groups
} as const;
```

## Module Creation (4-file pattern)

```
src/<module>/
├── <module>.types.ts       # interface XPayload, XResponse
├── <module>.factory.ts     # createXPayload(overrides?)
├── <module>.service.ts     # createX(request, token, overrides?, testName?)
└── index.ts                # export * + export as XService
```

Plus add endpoints to `src/constants/api.constants.ts`.

## Fixture Pattern (auto cleanup)

```typescript
// src/fixtures/<domain>.fixture.ts
import { test as base } from '@playwright/test';
export const test = base.extend<{ session: SessionData }>({
    session: async ({ request, accessToken }, use) => {
        const session = await Service.create(request, accessToken); // SETUP
        await use(session);
        try {
            await Service.cleanup(request, session.id, accessToken);
        } catch {} // TEARDOWN
    },
});
```

Test usage:

```typescript
import { test, expect } from '@src/fixtures/refinement.fixture';
test('foo', async ({ request, session }) => {
    /* session auto-ready */
});
```

## Error Assertion (negative test)

```typescript
import {
    parseErrorResponse,
    isApiErrorResponse,
    getFieldErrorMessage,
    getApiErrorMessage,
} from '@src/utils/error-handler';

expect(response.status()).toBe(HttpStatus.BAD_REQUEST);
const err = await parseErrorResponse(response);
expect(isApiErrorResponse(err)).toBe(true);
if (isApiErrorResponse(err)) {
    expect(err.success).toBe(false);
    expect(err.error.code).toMatch(/^ERR_\d+$/); // NOT hardcode "ERR_1000"
    expect(err.meta.requestId).toBeDefined(); // tracing
    const msg = getFieldErrorMessage(err, 'field') ?? getApiErrorMessage(err);
    expect(msg).toMatch(/expected-keyword/i);
}
```

ApiErrorResponse schema: `{ success: false, error: { code, message, details?: { fields? } }, meta: { timestamp, path, method, requestId } }`.

## Security Patterns

**401 (no auth)** — MUST fresh context, cookies persist trong fixture request:

```typescript
const fresh = await playwright.request.newContext({ baseURL: process.env.API_URL });
const response = await SomeService.getWithoutAuth(fresh, resourceId); // service *WithoutAuth() variant
await fresh.dispose();
expect(response.status()).toBe(HttpStatus.UNAUTHORIZED);
```

**403 (cross-user)** — MUST login User B separately:

```typescript
const { response: loginB } = await loginWithValidCredentials(request, {
    email: process.env.TEST_USER1_EMAIL!,
    password: process.env.TEST_USER1_PASSWORD!,
});
const userBToken = (await loginB.json()).accessToken;
const response = await request.get(endpoint, { headers: { Authorization: `Bearer ${userBToken}` } });
expect(response.status()).toBe(HttpStatus.FORBIDDEN);
```

## Naming + path conventions

| Item           | Convention                                                                                    |
| -------------- | --------------------------------------------------------------------------------------------- |
| File names     | `kebab-case.ts`                                                                               |
| Import         | `@src/*` alias (NOT `../../../src/*`)                                                         |
| Fixture import | `@src/fixtures/<domain>.fixture` (specific) hoặc `@src/fixtures` (merged hub)                 |
| Test path      | `tests/api/{domain}/{story-folder}/P{n}-{feature}.spec.ts`                                    |
| Priority       | `P0` critical, `P1` important, `P2` nice, `P3` perf — **split files theo priority (Rule #6)** |

## Logger format

```
🧪 [P0] Test name
   [POST] https://api-stg.sproux.ai/auth/signup
   📋 {"email":"test_...","password":"..."}
   📥 Expected: 201 | Actual: 201 → ✅ PASS
```

```typescript
import { TestLogger } from '@src/utils/test-logger';
const logger = TestLogger.getInstance();
logger.info(`🧪 ${testName}`);
```

## Change scenarios — sửa file nào?

| Scenario                | Files                                                                                                                                          |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| BE đổi base URL         | `.env` hoặc `src/utils/env-config.ts`                                                                                                          |
| BE đổi endpoint path    | `src/constants/api.constants.ts`                                                                                                               |
| BE thêm endpoint        | constants + `*.service.ts`                                                                                                                     |
| BE đổi req/resp format  | `*.types.ts` + `*.service.ts`                                                                                                                  |
| Thêm module mới         | 4 files trong `src/<module>/` + constants                                                                                                      |
| **Test fail vì BE bug** | **KHÔNG sửa test** — log bug theo [template](../templates/log-bug-api-template.md). Hierarchy of Truth: test-design > test code > BE > API-DOC |

## Pre-commit checklist

```
☐ Mọi API call qua *.service.ts (NO request.post direct)
☐ Mọi payload qua factory (NO hardcode)
☐ Mọi URL từ API_ENDPOINTS (NO hardcode)
☐ testName param truyền vào service call
☐ Import dùng @src/* alias
☐ Spec split P0/P1/P2 (Rule #6)
☐ Negative test dùng parseErrorResponse + isApiErrorResponse
☐ error.code regex /^ERR_\d+$/ (NOT hardcode)
☐ 401 test: fresh context + *WithoutAuth()
☐ 403 test: TEST_USER1 login (NOT same context)
☐ npx tsc --noEmit pass
☐ No `any`/`unknown`
```

## References

- [PROJECT-STRUCTURE.md](../PROJECT-STRUCTURE.md) — Full tutorial (2,063 LOC)
- [TEST-QUALITY-CHECKLIST.md](../TEST-QUALITY-CHECKLIST.md) — 9 Golden Rules + 41 items
- [qa-test-case/skill.md](../qa-test-case/skill.md) — Test design (happy/bad/edge, BVA, equivalence, decision table)
- [\_bmad-output/project-context.md](../../_bmad-output/project-context.md) — LLM-optimized context
- [api/](../api/) — BE contracts (Hierarchy of Truth #1)
