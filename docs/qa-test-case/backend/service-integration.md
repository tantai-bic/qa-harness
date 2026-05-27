# Backend — Service Integration (Rule #9)

Service layer integration đúng cách — `Rule #9` trong TEST-QUALITY-CHECKLIST. Chống wrong parameters / payload / method name.

## Hierarchy of Truth

Áp dụng cho **mọi BE test**:

| Rank | Source               | Authority                          |
| ---- | -------------------- | ---------------------------------- |
| 🥇   | Test Design Document | **HIGHEST** — requirements         |
| 🥈   | Test Code            | Verification (follows test-design) |
| 🥉   | Backend              | Implementation (can have bugs)     |
| 🏅   | API-DOC.md           | Documentation (can be outdated)    |

❌ **NEVER** change test assertion để pass khi BE sai. Rule #8 decision tree:

1. Test follows test-design? → Test CORRECT, BE WRONG → file BE bug.
2. Test deviates from test-design? → Fix test theo design.

## Service signature workflow

**TRƯỚC khi viết test gọi service:**

1. Read service file (`src/{module}/*.service.ts`)
2. Đếm parameters của target function
3. Verify type của mỗi param
4. Verify return type
5. Verify method name (KHÔNG đoán)

Common signature pattern trong project:

```ts
async function operationName(
  request: APIRequestContext,
  ...domain-params,                // resource IDs, payload
  accessToken: string,
  testName?: string,
  expectedStatus?: number
): Promise<{ response: APIResponse; body?: T }>
```

Vài variants:

- `accessToken` có thể trước hoặc sau domain params (check signature)
- `testName` BẮT BUỘC (F-1 lesson) — không bỏ
- `expectedStatus` optional với default

## F-1: No direct `request.post()`

❌ Anti-pattern:

```ts
const res = await request.post('/auth/login', { data: { email, password } });
```

✅ Service layer:

```ts
const { response, payload } = await LoginService.loginWithValidCredentials(
    request,
    { email, password },
    '[TC-AUTH-001] Login'
);
```

**Why:** TestLogger output, auth pattern, verify pattern, security newContext, consistent error handling.

## HTTP status semantics

Hook `verify-status-code-semantics.sh` enforces:

| Status           | Meaning                                     | Anti-pattern                             |
| ---------------- | ------------------------------------------- | ---------------------------------------- |
| 200              | Resource exists + returned                  | Test name "not found" assert 200 → E-NF1 |
| 200 + `data: []` | Resource empty (valid query, no items)      | Test name "empty" assert 404 → E-NF2     |
| 201              | Resource created                            | Signup returns 201 NO body per contract  |
| 204              | Success no content                          | Logout, DELETE                           |
| 400              | Bad request (format/validation)             |                                          |
| 401              | Unauthenticated (no/invalid token)          | Cookie leak (F-1 bonus) misleads to 200  |
| 403              | Authenticated but forbidden (locked / IDOR) |                                          |
| 404              | Resource NOT found (different ID)           | Don't confuse with 200+empty             |
| 409              | Conflict (duplicate, invalid state)         | Phase B re-call `ERR_1001`               |
| 422              | Unprocessable entity (semantic)             |                                          |
| 429              | Rate limited                                |                                          |
| 500              | Server error — **always a bug**             | Hook reject 500 in tests                 |

❌ Same assertion accept both 200 OR 404 = ambiguous (E-NF3). Phải decide theo test intent.

## Verify pattern (`verifyXxxResponseStructure`)

Mỗi service có verifier function:

- `verifyLoginResponseStructure(body)` — struct + non-empty fields
- `verifyValidationResponseStructure(body)` — `id`, `campaignId`, `selectedPlatforms[]`, dates
- `verifyTacticsResponseStructure(tactics[])` — required fields per tactic
- `verifyShortIdFormat(shortId)` — LP shortId pattern
- `verifyCookieHeaders(response)` — security flags

Use verifier instead of inline assertions when checking shape only.

## Checklist (Rule #9)

```
☐ Đã Read service file before writing test (không đoán signature)
☐ Đếm params đúng (vd 4 args không phải 3)
☐ Types đúng (string vs number, optional vs required)
☐ Method name đúng (vd `signupWithValidData` không phải `signupWithEmail`)
☐ `testName` parameter included (F-1 lesson)
☐ `expectedStatus` parameter set nếu non-default
☐ Payload structure khớp factory output
☐ Hierarchy of Truth: test follows test-design, NOT backend
☐ Status code semantics đúng (200 vs 404 vs 200+empty)
☐ NO direct `request.post()` — đi qua service (F-1)
☐ NPM `npx tsc --noEmit` pass
```

## See also

- [`/docs/TEST-QUALITY-CHECKLIST.md`](../../TEST-QUALITY-CHECKLIST.md) Rule #8 + Rule #9
- [`/CLAUDE.md`](../../../CLAUDE.md) F-1 (no direct request.post)
- [security.md](./security.md) — security service patterns
