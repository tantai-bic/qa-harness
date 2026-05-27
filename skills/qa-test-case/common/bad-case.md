# Bad Case — Negative / Error Path

System PHẢI reject với 4xx + error body chuẩn. Phần catch bug quan trọng nhất.

## Definition

Bad case = BE reject + trả error info:

- Input invalid (format/constraint/business rule)
- Auth fail (missing/wrong token, role không đủ)
- Resource missing (404) hoặc conflict (409)
- Rate limit (429)

**Khác [edge-case](./edge-case.md):** bad = 4xx expected. Edge = 2xx vẫn accept với input bất thường.

## Pattern

```typescript
import {
    parseErrorResponse,
    isApiErrorResponse,
    getFieldErrorMessage,
    getApiErrorMessage,
} from '@src/utils/error-handler';

test('[P0][TC-XXX-006] reject <reason> → 4xx', async ({ request, mockCampaign }) => {
    const payload = createInvalidXxxPayload();
    const response = await XxxService.createWithPayload(
        request,
        mockCampaign.accessToken,
        mockCampaign.campaignId,
        payload,
        '[P0][TC-XXX-006] Bad'
    );

    expect(response.status()).toBe(HttpStatus.BAD_REQUEST);

    const err = await parseErrorResponse(response);
    expect(isApiErrorResponse(err)).toBe(true);
    if (isApiErrorResponse(err)) {
        expect(err.success).toBe(false);
        expect(err.error.code).toMatch(/^ERR_\d+$/); // NOT hardcode code
        expect(err.meta.requestId).toBeDefined(); // tracing
        const msg = getFieldErrorMessage(err, 'field') ?? getApiErrorMessage(err);
        expect(msg).toMatch(/expected-keyword/i);
    }
});
```

## 6 Categories

| Category      | HTTP | Trigger                  | Example                                       |
| ------------- | ---- | ------------------------ | --------------------------------------------- |
| VALIDATION    | 400  | Field format/constraint  | `platforms: []`, `email: "x@"`, `duration: 0` |
| AUTHN         | 401  | Missing/invalid token    | No `Authorization`, expired JWT               |
| AUTHZ         | 403  | User B → User A resource | Cross-user campaign access                    |
| NOT_FOUND     | 404  | Resource missing         | Non-existent UUID                             |
| CONFLICT      | 409  | State conflict           | Published rồi → không edit                    |
| UNPROCESSABLE | 422  | Business rule fail       | Goal $50 < min $100                           |

## Coverage by priority

| Priority | Bad cases                                                                                |
| -------- | ---------------------------------------------------------------------------------------- |
| P0       | AUTHN (no token + invalid token), AUTHZ cross-user, critical VALIDATION (empty required) |
| P1       | Invalid partitions ([equivalence](./equivalence-partition.md)), 422 business, 404, 409   |
| P2       | Edge invalid (case-sensitivity, legacy values), biên ±1                                  |

P0 file PHẢI ≥2 bad case (1 auth + 1 validation).

## Anti-patterns

```typescript
// ❌ Chỉ check status (score error-parsing-depth = 0.15 — observed v4 without-hooks)
expect(response.status()).toBe(400); // MISSING: error.code, .message, .meta.requestId

// ❌ Hardcode error code — BE đổi → test break
expect(error.error.code).toBe('ERR_1000'); // → toMatch(/^ERR_\d+$/)

// ❌ 401 dùng same auth context (cookies persist)
const response = await request.get(endpoint); // returns 200, not 401!
// → fresh playwright.request.newContext() + service *WithoutAuth() (xem backend/security.md)

// ❌ 403 dùng cùng test context
const userB = mockCampaign; // NOT truly different user
// → login User B từ TEST_USER1_EMAIL/.env

// ❌ Sửa test khi BE bug
expect(response.status()).toBe(201); // test-design nói 400 → BE bug, log theo template
```

## Project examples

| Feature          | Bad case (P0)                                                                         |
| ---------------- | ------------------------------------------------------------------------------------- |
| Signup           | `email: "invalid"` → 400 + field "email"                                              |
| Login            | wrong password → 401                                                                  |
| Phase B Platform | `platforms: []` → 400, `["TWITTER"]` → 400 (legacy), no token → 401, cross-user → 403 |
| Campaign publish | published rồi → 409, Phase B chưa complete → 422                                      |

## Checklist

```
☐ Status đúng category (400/401/403/404/409/422)
☐ parseErrorResponse + isApiErrorResponse used
☐ error.code regex /^ERR_\d+$/ (NOT hardcode)
☐ error.meta.requestId asserted
☐ getFieldErrorMessage cho field-level (400)
☐ 401: fresh context + *WithoutAuth()
☐ 403: User B từ TEST_USER1_EMAIL
☐ KHÔNG sửa test khi BE wrong — log bug
```

## Related

- [equivalence-partition](./equivalence-partition.md) — invalid partitions
- [decision-table](./decision-table.md) — multi-condition bad case
- [backend/security.md](../backend/security.md) — 401/403/IDOR detail
- [backend/injection-xss.md](../backend/injection-xss.md) — SQLi/XSS = bad case nâng cao
- [happy-case](./happy-case.md) · [edge-case](./edge-case.md)
