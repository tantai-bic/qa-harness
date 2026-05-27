# Common — Pre-data (Test data setup)

Áp dụng cho **cả API + E2E**.

## Nguyên tắc

| Rule                      | Lý do                                                                                             |
| ------------------------- | ------------------------------------------------------------------------------------------------- |
| **Factory > literal**     | `createSignupPayload()` thay vì `{email:'test@x.com', ...}`. Parallel-safe, unique. F-2 incident. |
| **Unique per test**       | `generateUniqueEmail()` = `test_{timestamp}_{random}@example.com`. Tránh data drift giữa tests.   |
| **Shared `test-data.ts`** | Reuse fixture constants (giá trị biên, payload mẫu). DRY — Rule #5.                               |
| **Fresh state per case**  | Phase B mock single-shot → mỗi test cần fresh `createMockCampaign` (BE-CONSTRAINT-001).           |

## Checklist

```
☐ Identified test data needed (payloads, IDs, files, env-specific values)
☐ Tất cả unique IDs từ factory (KHÔNG hardcode `test@example.com`)
☐ Reuse từ test-data.ts nếu sẵn có (DRY)
☐ Edge values pre-defined: MIN-1, MIN, MIN+1, MAX-1, MAX, MAX+1
☐ Malicious payloads pre-defined: XSS / SQLi / oversized / null
☐ Multi-user data isolation: TEST_USER1..10 cho parallel hoặc fresh signup
```

## Common factory functions

| Domain             | Factory · Module                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------- |
| User signup        | `src/auth/signup/signup.factory.ts` → `createSignupPayload`                                       |
| Campaign           | `src/campaign/campaign.factory.ts` → `createMockCampaignPayload` · `generateCampaignId` (UUID v7) |
| Validation tactics | `src/validation/tactics/tactics.factory.ts` → `createTacticsPayloadWith(types)`                   |
| Poll               | `src/poll-tactic/poll-tactic.factory.ts` → `createYoutubePollUrl` · `createPollResultPayload`     |
| Email survey       | `src/validation/email-survey/email-survey.factory.ts`                                             |
| Goal/Pledge        | `src/goal/`, `src/pledge/` factories                                                              |

## See also

- [pre-condition.md](./pre-condition.md) — state probe trước assert
- [output-artifacts.md](./output-artifacts.md) — file structure + naming
- [`/CLAUDE.md`](../../../CLAUDE.md) F-2 incident
