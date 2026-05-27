# Happy Case — Critical Successful Path

P0 must-have. Verify luồng thành công lý tưởng + side effects.

## Definition

Happy case = 1 representative thoả mãn:

- Input valid ([equivalence-partition](./equivalence-partition.md))
- Pre-condition đúng state ([pre-condition](./pre-condition.md))
- Output 2xx + body schema match
- Side effect triggered (DB write, email sent, event emitted)

**KHÔNG phải:** mọi variant valid (→ equivalence) · mọi field combo (→ [decision-table](./decision-table.md)) · biên ±1 (→ [boundary-value](./boundary-value.md)).

## Pattern

```typescript
test('[P0][TC-XXX-001] should <verb> with valid input → 2xx', async ({ request, mockCampaign }) => {
    const testName = '[P0][TC-XXX-001] Happy';
    const payload = createXxxPayload(); // factory: valid + unique

    const { response, body } = await XxxService.create(
        request,
        mockCampaign.accessToken,
        mockCampaign.campaignId,
        payload,
        testName
    );

    expect(response.status()).toBe(HttpStatus.CREATED);
    expect(body).toBeDefined();
    expect(body!.id).toBeTruthy(); // resource created
    expect(body!.field).toBe(payload.field); // input persisted
    expect(body!.createdAt).toBeTruthy(); // timestamp set
});
```

## Coverage

| Aspect                     | Count  | Note               |
| -------------------------- | ------ | ------------------ |
| Main use case              | 1      | Critical path      |
| Read-back (GET after POST) | 1      | Verify persistence |
| Distinct entry points      | 1 each | Create vs upsert   |

Total **2-5 happy cases trong P0**. KHÔNG >7.

## Project examples

| Feature               | Happy case                                                   |
| --------------------- | ------------------------------------------------------------ |
| Signup                | POST valid email+password → 201 + user in DB                 |
| Login                 | POST valid creds → 200 + JWT + cookie set                    |
| Phase B Platform save | POST 2 platforms → 201 + validation.id + selectedPlatforms[] |
| Phase B Platform GET  | GET after POST → 200 + matching array                        |

## Anti-patterns

```typescript
// ❌ Quá nhiều happy variants
test('[P0] save 1 platform', ...);
test('[P0] save 2 platforms', ...);  // → move sang P1 equivalence

// ❌ Không assert side effect
expect(response.status()).toBe(201);  // MISSING: body, persistence

// ❌ Tên test mơ hồ
test('[P0] tests login', ...);  // → [TC-AUTH-001] login với email/password hợp lệ → 200 + accessToken
```

## Checklist

```
☐ Setup dùng factory (NO hardcode)
☐ Setup dùng fixture cleanup
☐ testName param truyền vào service
☐ Assert HTTP status
☐ Assert body shape (id, timestamps, ≥1 field persisted)
☐ Assert side effect (DB write hoặc GET after POST)
☐ TC-ID format TC-XXX-NNN với [P0] prefix
☐ KHÔNG test biên / invalid / edge → P1/P2
```

## Hierarchy of Truth

Verify test-design, KHÔNG infer từ BE. BE return 200 mà test-design nói 201 → **BE bug** (log theo [template](../../../../docs/templates/log-bug-api-template.md)), KHÔNG sửa test.

## Related

- [equivalence-partition](./equivalence-partition.md) — chọn ĐẠI DIỆN valid partition
- [pre-data](./pre-data.md) · [pre-condition](./pre-condition.md) — setup
- [bad-case](./bad-case.md) — negative path
- [edge-case](./edge-case.md) — unusual valid
