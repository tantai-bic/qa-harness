# API Patterns — Service + Factory + Constants + Fixture

> Layer cốt lõi cho API tests. Pair với [architecture](./architecture.md) + [helpers](./helpers.md).

## 3 Core Patterns

### Service Pattern (mandatory)

```typescript
// ❌ Direct API call
await request.post('https://api.example.com/auth/signup', { data });

// ✅ Service wrapper
const { response, payload } = await <AuthService>.signupWithValidData(request, undefined, testName);
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
await request.post('https://api.example.com/refinements/start');

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
import { test, expect } from '@src/fixtures/<feature>.fixture';
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
