# Common — Pre-condition (Setup checklist trước assertion)

Áp dụng cho **cả API + E2E**.

## Nguyên tắc

| Rule                               | Apply                                                                                         |
| ---------------------------------- | --------------------------------------------------------------------------------------------- |
| **Verify state BEFORE assert**     | Probe `GET` endpoint xác minh state có sẵn (F-3 lesson — fixture yield khi BE chưa seed xong) |
| **Idempotent setup**               | Setup phải chịu được retry — re-run không tạo state khác                                      |
| **One-way transitions documented** | Vd Phase B `draft → running` không reset được → seed fresh per test                           |
| **Cleanup khi cần**                | `abandonSession` cho refinement, `removeDevice` cho session                                   |

## Common pre-condition patterns

| Test scope        | Pre-condition                                                                               |
| ----------------- | ------------------------------------------------------------------------------------------- |
| Authenticated API | `accessToken` từ `loginUser` / `signupFreshCreator`                                         |
| Phase B test      | Phase A campaign created + Phase B `status=draft`                                           |
| Phase C test      | Phase B `status=completed` (mock với `status:'completed'` hoặc real `/refining-completion`) |
| Phase D test      | Phase C published + funding success                                                         |
| Dashboard test    | Creator có data → `seedFreshCampaignForTasks` để anti-drift                                 |
| Pagination test   | ≥ N items trong list (assert `length >= expectedPage * limit`)                              |
| Lockout test      | Pre-locked account `TEST_USER_EMAIL_BLOCK` hoặc 5× `loginWithInvalidCredentials`            |

## Precondition probe pattern (F-3 fix)

```ts
// Trong fixture, TRƯỚC `await use(...)`
const { body } = await getCampaign(request, campaignId, accessToken);
if (body?.currentPhase !== 'PHASE_A') {
    throw new Error(`Setup invariant violated: expected PHASE_A, got ${body?.currentPhase}`);
}
await use({ campaignId, accessToken });
```

## Checklist

```
☐ Pre-condition rõ ràng cho từng test scope
☐ Probe state BEFORE yield/assert (F-3)
☐ Setup idempotent — retry không corrupt state
☐ One-way transitions documented và respected
☐ Cleanup path nếu test mutate shared state
```

## See also

- [pre-data.md](./pre-data.md)
- [`docs/roadmap/campaign/`](../../roadmap/campaign/) — Phase A/B/C/D upstream chain
- F-3 incident trong [`/CLAUDE.md`](../../../CLAUDE.md)
