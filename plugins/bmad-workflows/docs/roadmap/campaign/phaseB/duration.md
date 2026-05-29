# Phase B → Module: Select Duration

Set validation runtime duration (3-14 days) và **trigger** transition `draft → running` qua `POST /refining-completion`. Bước **cuối cùng** của Phase B setup — sau bước này validation chính thức chạy, setup APIs đều reject.

## Scope

| Field          | Value                                                               |
| -------------- | ------------------------------------------------------------------- |
| Duration API   | `PATCH /campaigns/:cId/validations/:vId`                            |
| Start API      | `POST .../validations/:vId/refining-completion`                     |
| Required state | `draft` (cả PATCH duration + POST refining-completion)              |
| Output         | `durationDays`, `startedAt`, `endedAt` (computed), state transition |

## Upstream

| Cần                           | Nguồn                                                                       |
| ----------------------------- | --------------------------------------------------------------------------- |
| `accessToken`                 | [`../../auth/signIn.md`](../../auth/signIn.md)                              |
| `campaignId` + `validationId` | [Platform](./platform.md)                                                   |
| Tactics saved                 | [Tactics](./tactics.md) — ≥1 tactic                                         |
| Tactic-specific setup done    | LP generated · poll URL saved · email-list ≥1 recipient (per tactic in mix) |

## Downstream

| Bước tiếp                                         | Note                                                                         |
| ------------------------------------------------- | ---------------------------------------------------------------------------- |
| Phase B `running` state                           | BE auto-transition `running → completed` sau duration days                   |
| Public tracking active                            | LP visit · email open · poll vote → đóng góp metrics                         |
| [Dashboard Validation](./dashboard-validation.md) | Review traffic light zone real-time                                          |
| → **Phase C**                                     | Khi `status=completed` → unlock `POST /campaigns/:id/goals/start-refinement` |

## Endpoints

```
PATCH  /campaigns/:cId/validations/:vId                       ← set durationDays
POST   /campaigns/:cId/validations/:vId/refining-completion   ← start (draft → running)
```

| Endpoint                                  | Method | Gate                           |
| ----------------------------------------- | ------ | ------------------------------ |
| `VALIDATION.updateDuration(cId, vId)`     | PATCH  | 🔒 duration set (`draft` only) |
| `VALIDATION.refiningCompletion(cId, vId)` | POST   | 🔄 `draft → running` (one-way) |

## Service layer (`src/validation/duration/duration.service.ts`)

| Function                                                                                  | Mục đích                                    |
| ----------------------------------------------------------------------------------------- | ------------------------------------------- |
| `updateDuration(request, cId, vId, durationDays, accessToken, testName, expectedStatus?)` | PATCH duration                              |
| `startValidation(request, cId, vId, accessToken, testName, expectedStatus?)`              | POST `/refining-completion`                 |
| `updateDurationWithoutAuth` · `startValidationWithoutAuth`                                | 401 tests                                   |
| `verifyDateCalculation(startedAt, endedAt, durationDays)`                                 | Assert `endedAt = startedAt + durationDays` |
| Factory                                                                                   | `duration.factory.ts`                       |

## Types

| Type                         | Note                                                                                     |
| ---------------------------- | ---------------------------------------------------------------------------------------- |
| `DurationValidationResponse` | `{id, campaignId, selectedPlatforms, durationDays, startedAt, endedAt, ...}` — camelCase |
| `DURATION_DAYS`              | `{MIN:3, MAX:14}`                                                                        |

## Constraints

- **`durationDays` range 3-14** — 2 → 400, 15 → 400.
- **Type number** — string `"7"` → 400 (BE strict).
- **PATCH duration phải trước `/refining-completion`** — call `/refining-completion` không set duration trước → 400 hoặc dùng default? (Check API contract — `docs/sprint2/squad-coca/` cho update logic).
- **Lock sau publish** — sau start, PATCH duration → 403 Forbidden (Story 04.1.4 — `createPublishedCampaignSession` verifies).
- **One-way `running` transition** — `/refining-completion` chạy 1 lần. Call 2 → 409 hoặc `ERR_1001`.
- **Tactic-specific prerequisites** — `/refining-completion` reject nếu tactics chưa setup đủ:
    - `landing_page` cần generated
    - poll tactics cần `pollUrl` saved
    - `email_survey` cần ≥1 recipient
- **Auto end** — BE auto-transition `running → completed` sau `endedAt` (cron/scheduler). Test e2e khó vì wait 3-14 days → dùng mock validation với `status:'completed'` thay vì wait.

## Testing methods

| Method                | Apply                                                                                       |
| --------------------- | ------------------------------------------------------------------------------------------- |
| Boundary              | `durationDays`: 2, 3, 4, 13, 14, 15                                                         |
| Equivalence partition | Valid number 3-14 · invalid: string, null, negative, float, 0                               |
| State transition      | `draft → running` (one-way), reject 2nd call, post-start PATCH lock                         |
| Decision table        | Start gating: tactic mix × setup completeness (LP gen Y/N, poll URL Y/N, recipients ≥1 Y/N) |
| Date math             | `verifyDateCalculation` — endedAt vs startedAt + N days                                     |
| Security              | 401 unauth · cross-user vId · negative `durationDays` injection                             |

## Project references

- [`docs/sprint2/squad-coca/`](../../../sprint2/squad-coca/) — duration/transition contracts
- [`docs/transition-to-phase-C/`](../../../transition-to-phase-C/) — Phase B → C handoff
- `src/goal/goal.helpers.ts` → `createPublishedCampaignSession(request, accessToken, durationDays, testName)` — full helper Phase A→B→C→publish (uses duration set)
