# Common — Edge Case (Unusual but Valid)

Test scenario **input vẫn valid** nhưng bất thường — race condition, concurrent access, unicode/emoji, large payload, timezone, retry idempotency. BE PHẢI handle đúng (không crash, không corrupt data).

## 🎯 Định nghĩa

**Edge case** ≠ bad case:

- Bad case = BE **PHẢI reject** (4xx expected) — input invalid per design.
- Edge case = BE **PHẢI accept** (2xx expected) — input valid nhưng hiếm/lạ.

**Edge case** ≠ boundary value:

- Boundary value = test ±1 quanh constraint số (MIN-1, MIN, MIN+1, MAX-1, MAX, MAX+1)
- Edge case = combinations/states không thuộc boundary đơn (concurrent, encoding, time-sensitive, retry)

## 📦 Categories — 7 nhóm edge case

| Category             | Mô tả                                               | Project example                                                                  |
| -------------------- | --------------------------------------------------- | -------------------------------------------------------------------------------- |
| **CONCURRENCY**      | 2+ requests cùng lúc trên same resource             | 2 user pledge cùng tier cuối → race condition?                                   |
| **IDEMPOTENCY**      | Cùng request gửi nhiều lần → side effect chỉ 1 lần  | POST pledge × 3 (network retry) → 1 pledge, không trùng                          |
| **UNICODE/I18N**     | Multi-byte chars, RTL text, emoji, control chars    | Title `🎉 Chiến dịch tiếng việt` , Arabic, zero-width space                      |
| **LARGE PAYLOAD**    | Near max-size string/array                          | description 65535 chars (DB TEXT max), title với 256-char unicode (4 bytes/char) |
| **TIME-SENSITIVE**   | Timezone, DST transition, leap year, midnight cross | Pledge tại 23:59:59 → BE midnight tally đúng?                                    |
| **STATE-RACE**       | State transition mid-flight                         | Campaign published trong khi user còn editing draft                              |
| **RETRY/RESUMPTION** | Network blip, browser refresh, session resume       | POST tactics rồi network drop → user retry → duplicate?                          |

## 📋 Pattern theo từng category

### CONCURRENCY

```typescript
test('[P2][TC-XXX-301] concurrent pledge → consistent state', async ({ request }) => {
    const [r1, r2] = await Promise.all([
        PledgeService.create(request, tier1, payload, '[A] concurrent'),
        PledgeService.create(request, tier1, payload, '[B] concurrent'),
    ]);
    // Either both succeed (BE handles concurrency) hoặc one returns 409
    const statuses = [r1.response.status(), r2.response.status()].sort();
    expect(statuses).toEqual(expect.arrayContaining([HttpStatus.CREATED]));
    // Verify total pledges = 2 (no lost write)
});
```

### IDEMPOTENCY

```typescript
test('[P2][TC-XXX-302] idempotent POST → no duplicate side effect', async ({ request }) => {
    const payload = createPledgePayload({ idempotencyKey: 'unique-key-001' });
    const r1 = await PledgeService.create(request, ..., payload);
    const r2 = await PledgeService.create(request, ..., payload);  // same key

    expect(r1.response.status()).toBe(HttpStatus.CREATED);
    expect(r2.response.status()).toBe(HttpStatus.OK);  // idempotent replay → 200
    expect(r1.body!.id).toBe(r2.body!.id);              // same resource
});
```

### UNICODE/I18N

```typescript
test('[P2][TC-XXX-303] unicode title → persist + render correct', async ({ request }) => {
    const payload = createCampaignPayload({ title: '🎉 Chiến dịch Việt Nam العربية' });
    const { response, body } = await CampaignService.create(request, payload);
    expect(response.status()).toBe(HttpStatus.CREATED);
    expect(body!.title).toBe(payload.title); // round-trip không bị mojibake
    expect(body!.title.length).toBeGreaterThan(0);
});
```

### LARGE PAYLOAD

```typescript
test('[P2][TC-XXX-304] near-max description (65000 chars) → 201', async ({ request }) => {
    const payload = createCampaignPayload({ description: 'a'.repeat(65000) });
    const { response } = await CampaignService.create(request, payload);
    expect(response.status()).toBe(HttpStatus.CREATED);
});
```

### TIME-SENSITIVE

```typescript
test('[P2][TC-XXX-305] pledge at midnight UTC → counted correct date', async ({ request }) => {
    // Mock or wait until 23:59:55 UTC, then POST at 23:59:59
    const payload = createPledgePayload({ scheduledAt: '2026-12-31T23:59:59.999Z' });
    const { response, body } = await PledgeService.create(request, payload);
    expect(response.status()).toBe(HttpStatus.CREATED);
    expect(body!.createdAt.startsWith('2026-12-31')).toBe(true); // không lệch sang 2027-01-01
});
```

### STATE-RACE

```typescript
test('[P2][TC-XXX-306] edit campaign khi đang publish → 409 hoặc no-op', async ({ request }) => {
    const draftId = mockCampaign.campaignId;
    const [edit, publish] = await Promise.all([
        CampaignService.update(request, draftId, { title: 'New' }),
        CampaignService.publish(request, draftId),
    ]);
    // BE phải atomic: either edit succeed trước publish, OR publish trước → edit 409
    const editStatus = edit.response.status();
    expect([HttpStatus.OK, HttpStatus.CONFLICT]).toContain(editStatus);
});
```

### RETRY/RESUMPTION

```typescript
test('[P2][TC-XXX-307] resume session sau network drop → state intact', async ({ request, session }) => {
    // Submit Q1, simulate network drop, retry submit
    await RefinementService.respond(request, session.sessionId, 'Q1', 'answer1');
    // Simulate: retry same answer (network blip giả lập)
    const { response } = await RefinementService.respond(request, session.sessionId, 'Q1', 'answer1');
    // BE phải dedupe — vẫn 200/202 (idempotent) không tạo Q1 trùng
    expect([HttpStatus.OK, HttpStatus.ACCEPTED]).toContain(response.status());
});
```

## 🎯 Coverage strategy

| Priority | Edge cases bao gồm                                                         |
| -------- | -------------------------------------------------------------------------- |
| **P0**   | KHÔNG. Edge case quá rộng cho P0                                           |
| **P1**   | Critical idempotency (payment-like operation), basic unicode (title field) |
| **P2**   | Concurrency, large payload, timezone, retry — nice-to-have                 |
| **P3**   | Stress test, long-running session, memory leak                             |

→ Edge case **default P2**. Move lên P1 chỉ khi business critical (payment, audit log).

## 📝 Project examples

| Feature           | Edge case (P2)                                                                                  |
| ----------------- | ----------------------------------------------------------------------------------------------- |
| Pledge            | concurrent same-tier (last item), idempotency key (network retry), large pledge amount near $1M |
| Campaign create   | title với emoji + Vietnamese, description 64KB, scheduledAt timezone DST                        |
| Refinement Q1-Q7  | resume sau network drop (cùng answer → no dup), Q1 với multi-byte unicode                       |
| Phase B Platform  | concurrent POST 2 user same campaign (race), upsert sau 24h (TTL?)                              |
| Hero media upload | 10MB file, concurrent upload, retry với same media-id                                           |

## 🔥 Anti-patterns

### ❌ Edge case làm P0

```typescript
// BAD — edge case kéo budget P0 (must-pass mỗi commit)
test('[P0] concurrent pledge race condition', ...);
```

→ Move sang P2. P0 chỉ critical happy + critical bad case.

### ❌ Test concurrency với 1 thread

```typescript
// BAD — sequential await, không thực sự concurrent
const r1 = await PledgeService.create(...);
const r2 = await PledgeService.create(...);
```

→ Dùng `Promise.all` để 2 request fire cùng lúc.

### ❌ Hardcode timezone

```typescript
// BAD — test break ở môi trường timezone khác
expect(body.createdAt).toBe('2026-12-31T23:59:59.999+07:00');
```

→ Assert UTC + use ISO. Stage CI có thể UTC, local có thể GMT+7.

### ❌ Large payload không cleanup

```typescript
// BAD — tạo campaign 64KB rồi để lại → DB pollution
```

→ Fixture auto-cleanup (mockCampaign teardown).

## ✅ Checklist edge case

```
☐ Đã có happy + bad case trước (P0/P1) — edge KHÔNG phải first pass
☐ Promise.all cho concurrency tests
☐ Idempotency: same key gửi 2 lần → expect dedup behavior
☐ Unicode: include emoji + Vietnamese + RTL nếu i18n support
☐ Large payload: gần max constraint (DB schema TEXT/VARCHAR limits)
☐ Time-sensitive: assert UTC, không local timezone
☐ Cleanup: fixture teardown, không leave large data
☐ Priority đúng P2 (hoặc P1 nếu business critical)
☐ Edge case fail KHÔNG block release (nice-to-have) — trừ khi payment/audit
```

## 🎯 Khi nào KHÔNG cần edge case

- Prototype/throw-away script
- Internal admin tool ít user
- Feature đã có observability mạnh (sentry, datadog catch runtime)
- Time-sensitive với test infra không control được time (skip thay vì flaky)

## 🔗 Related modules

- `boundary-value.md` — Biên ±1 (P1) — KHÁC edge case
- `state-transition.md` — State machine — overlap với STATE-RACE category
- `decision-table.md` — Multi-condition — overlap với CONCURRENCY combos
- `happy-case.md` — Critical path (P0)
- `bad-case.md` — Reject path (P0/P1)
- `pre-data.md` — Factory cho large/unicode/edge data
