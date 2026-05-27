# Phase B → Module: Poll Tactics

Creator chạy poll trên platform thật (YouTube Community Poll / Instagram Poll Story / X Poll) → manually submit kết quả vào platform. Tactic types: `youtube_poll`, `instagram_poll`, `x_poll`. Result = `totalVotes` + `preferredOptionPercent` → đóng góp vào traffic light zone.

## Scope

| Field          | Value                                                                                                  |
| -------------- | ------------------------------------------------------------------------------------------------------ |
| API base       | `/campaigns/:cId/validations/:vId/tactics/:tId/*`                                                      |
| Required state | Phase B — `status=draft` cho save URL, `status=running` cho submit results                             |
| Output         | `pollUrl`, `pollResult: {totalVotes, preferredOptionPercent, submittedAt, reachCount, interestedRate}` |

## Upstream

| Cần                                                                                        | Nguồn                                                                                   |
| ------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------- |
| `accessToken`                                                                              | [`../../auth/signIn.md`](../../auth/signIn.md)                                          |
| `campaignId` + `validationId` + `tacticId` (type=`youtube_poll`/`instagram_poll`/`x_poll`) | [Tactics](./tactics.md)                                                                 |
| Real poll URL (YouTube/IG/X)                                                               | Creator manually create poll trên platform thật. Test: `createYoutubePollUrl()` factory |

## Downstream

| Bước tiếp                                         | Mục đích                                                                             |
| ------------------------------------------------- | ------------------------------------------------------------------------------------ |
| [Duration](./duration.md) + start validation      | Cần poll URL saved trước start (đa số tactic-specific)                               |
| Submit results (runtime)                          | Sau khi platform poll closed, creator submit `totalVotes` + `preferredOptionPercent` |
| [Dashboard Validation](./dashboard-validation.md) | Poll result đóng góp vào zone (rate = `preferredOptionPercent`)                      |
| Reminder                                          | `POST/GET .../reminder` cho submit deadline                                          |

## Endpoints

```
# Setup
GET    .../tactics/:tId/poll-content      ← BE generate poll content (question + options)
PATCH  .../tactics/:tId/poll-url          ← save real platform poll URL
GET    .../tactics/:tId                   ← tactic details (includes pollUrl + pollResult)

# Runtime
POST   .../tactics/:tId/results           ← submit poll results
GET    .../tactics/:tId/results           ← read results
POST   .../tactics/:tId/reminder          ← set reminder
GET    .../tactics/:tId/reminder          ← read reminder

# Mock
POST   /mock/poll-validations             ← skip real platform — preset metrics
```

| Endpoint                   | Method                   | Gate |
| -------------------------- | ------------------------ | ---- |
| `poll-content` GET         | 📖 generate (idempotent) |
| `poll-url` PATCH           | 🔒 setup                 |
| `results` POST             | ⚡ runtime (after start) |
| `results` GET · `reminder` | 📖 / ⚡                  |

## Service layer

### Real (`src/poll-tactic/poll-tactic.service.ts`)

| Function                                                                    | Mục đích                                       |
| --------------------------------------------------------------------------- | ---------------------------------------------- |
| `getPollContent`                                                            | BE generate poll question + options từ concept |
| `getTacticCards`                                                            | Tactic cards FE display                        |
| `getTacticDetails(request, cId, vId, accessToken, testName)`                | Full tactic data                               |
| `savePollUrl(request, cId, vId, tId, payload, accessToken, testName)`       | PATCH `/poll-url`                              |
| `submitPollResults(request, cId, vId, tId, payload, accessToken, testName)` | POST `/results`                                |
| `getPollResults`                                                            | Read submitted                                 |
| `setReminder` · `getReminder`                                               | Reminder CRUD                                  |

### Mock (`src/poll-tactic/mock-poll-validation.service.ts`)

Mock alternative cho fast setup zone-classification tests. Bypass real platform.

### Factory (`src/poll-tactic/poll-tactic.factory.ts`)

| Helper                                                          | Output                 |
| --------------------------------------------------------------- | ---------------------- |
| `createYoutubePollUrl()`                                        | Valid YouTube poll URL |
| `createInstagramPollUrl()`                                      | Valid IG URL           |
| `createXPollUrl()`                                              | Valid X URL            |
| `createPollResultPayload({totalVotes, preferredOptionPercent})` | Submit payload         |

## Types (`src/poll-tactic/poll-tactic.types.ts`)

| Type                 | Note                                                     |
| -------------------- | -------------------------------------------------------- |
| `PollContent`        | Question + options từ BE                                 |
| `PollResultPayload`  | `{totalVotes, preferredOptionPercent}`                   |
| `PollResultResponse` | `{totalVotes, preferredOptionPercent, submittedAt, ...}` |
| `TacticDetails`      | Tactic + nested `pollResult`                             |

## Constraints

- **Story 03.2.4 — Result Integrity** (Sprint 10):
    - `submittedAt` phải ISO 8601 UTC format (`YYYY-MM-DDTHH:mm:ss.sssZ`). Round-trip check: `new Date(submittedAt).toISOString() === submittedAt`.
    - **Idempotency Q13** — double concurrent submit cùng payload → both 201, single persisted record (BE treat as UPDATE not duplicate INSERT). `reachCount` không doubled.
- **Q18 — submittedAt server-set** — submit không cho phép client override timestamp.
- **`pollUrl` validation** — BE accept URL pattern khớp platform (YouTube/IG/X domain). Invalid URL → 400.
- **Poll URL save phải trước duration start** — save sau start → 4xx (setup gate).
- **`results` submit gating** — Story 03.2.4 decision table 10 scenarios (xem MEMORY `project_poll_result_submit_cases.md`): `pollUrl set?`, `tactic locked?`, `validation status?`, `result already submitted?`.
- **TC ID range** — `TC-4.20`..`TC-4.39` (Story 03.2.4 test design).

## Testing methods

| Method                | Apply                                                                                        |
| --------------------- | -------------------------------------------------------------------------------------------- |
| Boundary              | `totalVotes` 0/1/max · `preferredOptionPercent` 0/0.5/100/101 · submittedAt ISO format edges |
| Equivalence partition | Valid URLs vs invalid platform vs non-URL string                                             |
| State transition      | URL not-set → set → submitted → locked. Modal Confirm khi đổi tactic mix                     |
| Decision table        | Submit gating 10 scenarios (Story 03.2.4)                                                    |
| Security              | 401 cross-user submit · XSS in pollUrl · oversized payload                                   |
| Concurrency           | Double-submit idempotency (Q13) — 2 concurrent calls cùng tId                                |

## Project references

- [`docs/sprint_10/epic-03.2-poll-tactic/`](../../../sprint_10/epic-03.2-poll-tactic/) — full story specs + test design
- MEMORY auto-memory: `project_poll_result_submit_cases.md` (10-scenario decision table)
- MEMORY `project_total_votes_selector_pattern.md` · `project_zone_confidence_mapping.md` (FE)
