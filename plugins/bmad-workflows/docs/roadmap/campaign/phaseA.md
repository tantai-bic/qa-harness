# Phase A — Concept Refinement

Creator chuyển ý tưởng thô → concept structured (title / positioning / curriculum / pricing) qua AI Q1-Q7. Output: `conceptId` + concept data sẵn cho Phase B validate.

## 🎯 Default policy

> **DEFAULT = `createMockCampaign` (mock shortcut).** Áp dụng cho mọi test Phase B/C/D + dashboard + analytics + downstream features.
>
> **Real Q1-Q7 flow CHỈ dùng cho E2E Golden Flow** (1 test signature per release validate AI refinement UX end-to-end). Mọi test khác → mock.

Lý do: AI gen ~40s × N tests = bottleneck CI · non-determinism (AI output drift) · không cần concept content cho hầu hết feature tests.

## State

| Field                       | Value                                     |
| --------------------------- | ----------------------------------------- |
| `currentPhase`              | `PHASE_A`                                 |
| `operationalStatus`         | `IN_PROGRESS`                             |
| Refinement `session.status` | `in_progress` → `completed` (sau confirm) |

## Upstream (deps để vào Phase A)

| Cần                  | Nguồn                                                                      |
| -------------------- | -------------------------------------------------------------------------- |
| `accessToken`        | `loginUser` / `signupFreshCreator` (auth fixture)                          |
| `campaignId` UUID v7 | `generateCampaignId()` — BE validates format `00000000-0000-7000-8000-xxx` |

## Downstream (Phase A unlocks)

| Phase tiếp            | Endpoint gate                          | Điều kiện                                                                                       |
| --------------------- | -------------------------------------- | ----------------------------------------------------------------------------------------------- |
| **B** validation      | `POST /mock/validations`               | Phase B status=draft → fresh campaign only (F-3 lesson, BE chuyển running/completed sau 1 call) |
| **C** refinement/goal | `POST /campaigns/:id/refinement/start` | Concept confirmed (`POST /refinements/:id/confirm`)                                             |
| **D** delivery        | `POST /deliveries`                     | Sau Phase C publish + funding success                                                           |

## Real flow (production path, ~40s)

| #   | Endpoint                                         | Out                                                                |
| --- | ------------------------------------------------ | ------------------------------------------------------------------ |
| 1   | `POST /campaigns {title}`                        | `campaignId`                                                       |
| 2   | `POST /refinements/start {sessionId:campaignId}` | `sessionId` = `campaignId`                                         |
| 3   | `POST /refinements/:id/respond` × 7              | Q1-Q7 answers (dùng `getFixedPhaseAAnswers` tránh AI clarify loop) |
| 4   | Poll `GET /refinements/:id` 5s × 8 retries       | `concept` populated, status=`completed`                            |
| 5   | `POST /refinements/:id/confirm`                  | Concept locked                                                     |
| 6   | `POST /campaigns/:id/refinement/start`           | `goalId` → Phase C                                                 |

## Mock shortcut (skip Q1-Q7, ~1-2s)

| Endpoint               | Payload               | Response                                                                   |
| ---------------------- | --------------------- | -------------------------------------------------------------------------- |
| `POST /mock/campaigns` | `{campaignId, title}` | `{id, conceptId, currentPhase:'PHASE_A', operationalStatus:'IN_PROGRESS'}` |

BE XSS guard: `<script>` trong `title` → 400. Emoji / quotes / entities OK.

## Service / Factory / Helper layer

| Layer                 | File · Symbol                                                                                                                                            |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Service mock          | `src/campaign/campaign.service.ts` → `createMockCampaign()`                                                                                              |
| Service real          | `src/campaign/campaign.service.ts` → `createCampaign()`                                                                                                  |
| Service refinement    | `src/refinement/refinement.service.ts` → `startSession` · `submitResponse` · `completeAllQuestions` · `confirmConcept` · `getSession` · `abandonSession` |
| Factory               | `src/campaign/campaign.factory.ts` → `createMockCampaignPayload()` · `generateCampaignId()` UUID v7 · `generateCampaignTitle()`                          |
| Fixed answers Q1-Q7   | `src/goal/goal.helpers.ts` → `getFixedPhaseAAnswers()`                                                                                                   |
| Full real-flow helper | `src/goal/goal.helpers.ts` → `createPublishedCampaignSession()` (A→B→C→publish)                                                                          |
| Quick seed dashboard  | `src/creator-dashboard/seed/creator-state.helper.ts` → `seedFreshCampaignForTasks()`                                                                     |

## Types

| Type                                                             | File · Line                                        |
| ---------------------------------------------------------------- | -------------------------------------------------- |
| `MockCampaignPayload` · `MockCampaignResponse` · `CampaignPhase` | `src/campaign/campaign.types.ts`                   |
| `PhaseASummary`                                                  | `src/campaign/campaign.types.ts:148`               |
| `PhaseAConceptData` · `PhaseAPricing`                            | `src/campaign-goal/campaign-goal.types.ts:181-204` |

## Mocks available

| Mock       | Endpoint               | Effect                                                                   |
| ---------- | ---------------------- | ------------------------------------------------------------------------ |
| Skip Q1-Q7 | `POST /mock/campaigns` | Tạo campaign Phase A có concept data sẵn — standard cho test Phase B/C/D |

## Constraints (failure log)

- **F-5** — KHÔNG tự loop `submitResponse` Q1-Q7. Dùng `RefinementService.completeAllQuestions` (race condition).
- **F-1** — KHÔNG gọi `request.post()` thẳng vào endpoint refinement/campaign. Đi qua service layer (TestLogger + auth chuẩn).
- **F-3** — Sau `createMockCampaign`, KHÔNG yield ngay nếu downstream cần concept data. Probe `GET /campaigns/:id` xác minh trước.
- UUID v7 mandatory: prefix `00000000-0000-7000-8000-` + 12 hex (`generateCampaignId`).
- BE timeout cho `/mock/campaigns` set 30s (STG slow).
- AI concept gen polling: 5s × 8 retries (max 40s) trước khi throw.
- Mỗi probe Phase B event phải seed Phase A **fresh** (Phase B status=draft only-once per campaign).

## Khi nào dùng mock vs real?

**Rule:** mock là default. Real Q1-Q7 chỉ khi nằm trong matrix dưới đây.

| Use-case                                                                                                               | Dùng                                                  | Cost    |
| ---------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- | ------- |
| ⭐ **Default — mọi test Phase B/C/D, dashboard, analytics, downstream**                                                | `createMockCampaign`                                  | ~1-2s   |
| Creator dashboard với fresh campaign (anti data-drift)                                                                 | `seedFreshCampaignForTasks`                           | ~5s     |
| Phase C+ cần concept-derived auto-populate (description, curriculum, pricing) — **chỉ khi mock concept data không đủ** | `createPublishedCampaignSession` (real A→B→C→publish) | ~60-90s |
| **E2E Golden Flow** — 1 signature test per release validate AI refinement UX (Q1-Q7 → confirm → Phase C)               | `createCampaign` + Q1-Q7 real + `confirmConcept`      | ~40s    |
| Test Q1-Q7 / AI refinement logic itself (story 02.x epic)                                                              | `createCampaign` + Q1-Q7 real                         | ~40s    |

❌ KHÔNG dùng real Q1-Q7 cho: smoke tests, regression suite, dashboard tests, validation/tactic tests, pledge/delivery tests, security tests, NFR tests. Mock đủ cho tất cả.

## Endpoints reference (`src/constants/api.constants.ts`)

```
REFINEMENT.MOCK.CAMPAIGNS         POST /mock/campaigns
CAMPAIGN.LIST                     POST /campaigns
REFINEMENT.START                  POST /refinements/start
REFINEMENT.RESPOND(id)            POST /refinements/:id/respond
REFINEMENT.GET_SESSION(id)        GET  /refinements/:id
REFINEMENT.CONFIRM(id)            POST /refinements/:id/confirm
REFINEMENT.ABANDON(id)            POST /refinements/:id/abandon
CAMPAIGN.START_REFINEMENT(id)     POST /campaigns/:id/refinement/start   ← Phase A→C gate
```
