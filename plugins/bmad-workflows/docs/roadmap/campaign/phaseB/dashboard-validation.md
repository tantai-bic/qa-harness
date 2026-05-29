# Phase B → Module: Dashboard Validation (Review)

Review screen cho creator sau khi validation `running` / `completed`. Aggregate metrics từ tất cả tactics → **traffic light zone** classification (GREEN/YELLOW/RED/null). Đây là decision gate creator dùng để quyết định move sang Phase C (goal/publish).

## Scope

| Field          | Value                                                                               |
| -------------- | ----------------------------------------------------------------------------------- |
| API            | `GET /campaigns/:cId/validations/:vId/review`                                       |
| Required state | Any (read-only) — typically `running` hoặc `completed`                              |
| Output         | `ValidationReviewResponseDto` — combines validation + analytics + tactics + concept |

## Upstream

| Cần                           | Nguồn                                                           |
| ----------------------------- | --------------------------------------------------------------- |
| `accessToken`                 | [`../../auth/signIn.md`](../../auth/signIn.md)                  |
| `campaignId` + `validationId` | Tất cả module Phase B trước đó                                  |
| Validation state ≥ `running`  | [Duration](./duration.md) đã start                              |
| Tactic-specific data          | Mỗi tactic đã có data (LP visit · poll result · email register) |

## Downstream

| Bước tiếp                 | Note                                                                                                  |
| ------------------------- | ----------------------------------------------------------------------------------------------------- |
| Decision: move to Phase C | `trafficLightZone = GREEN` → confident publish · `YELLOW`/`RED` → reconsider · `null` → cần thêm data |
| **Phase C**               | `POST /campaigns/:cId/goals/start-refinement` — requires `status=completed`                           |

## Traffic light classification (decision table)

| `totalReach` | `interestRate` | Zone     | Confidence label    |
| ------------ | -------------- | -------- | ------------------- |
| < 50         | \*             | `null`   | "Insufficient data" |
| ≥ 50         | ≥ 20%          | `GREEN`  | "High confidence"   |
| ≥ 50         | 10-19%         | `YELLOW` | "Medium confidence" |
| ≥ 50         | < 10%          | `RED`    | "Low confidence"    |

⚠️ **FE renders zone qua confidence label text** (`High/Medium/Low confidence`) — KHÔNG qua text `GREEN`/`YELLOW`/`RED` (MEMORY `project_zone_confidence_mapping.md`). Tránh legend false-positive.

Static benchmark khác cho **poll-only display** (Sprint 12 Gap #2 per Figma): GREEN=68%, YELLOW=45%, RED=18% — NOT calculated from tactic mix, just visual reference.

## Endpoints

```
GET   /campaigns/:cId/validations/:vId/review     ← aggregate review data
GET   /campaigns/:cId/validations/:vId            ← raw validation (alternative)
```

| Endpoint                       | Method | Gate                     |
| ------------------------------ | ------ | ------------------------ |
| `VALIDATION.review(cId, vId)`  | GET    | 📖 read-only (any state) |
| `VALIDATION.getById(cId, vId)` | GET    | 📖 read-only             |

## Service layer (`src/validation/review/review.service.ts`)

| Function                                                                         | Mục đích   |
| -------------------------------------------------------------------------------- | ---------- |
| `getValidationReview(request, cId, vId, accessToken, testName, expectedStatus?)` | GET review |
| `getValidationReviewWithoutAuth`                                                 | 401 test   |

Alternative: `validation.service.ts` → `getValidationById` (raw shape, không aggregate).

## Types (`src/validation/validation.types.ts`)

| Type                          | Note                                                                                                      |
| ----------------------------- | --------------------------------------------------------------------------------------------------------- |
| `ValidationReviewResponseDto` | Full response — validation fields + analytics + `tactics[]` + concept fields                              |
| `ReviewTactic`                | `{id, type, reachCount, interestedCount, interestedRate, zone, isAutoTracked, trackingMethod, createdAt}` |
| `TrafficLightZone`            | `'GREEN'\|'YELLOW'\|'RED'` (per-tactic + overall)                                                         |
| `TrackingMethod`              | `'auto_tracked'\|'manual_input'`                                                                          |
| Analytics fields ở root       | `totalReach`, `totalInterested`, `overallInterestRate`, `trafficLightZone`                                |
| Concept fields ở root         | `title`, `marketPositioning`, `earlyPrice`, `regularPrice`, `earlyBirdLimit`                              |

⚠️ API returns **camelCase** không phải snake_case như spec doc.

## Constraints

- **Read-only** — không có POST/PATCH/DELETE.
- **`null` zone khi `totalReach < 50`** — insufficient data threshold.
- **`overallInterestRate = totalInterested / totalReach`** — float [0, 1].
- **Cross-tactic aggregate** — `totalReach` = sum tactics' `reachCount`; `totalInterested` = sum.
- **Tactic-level zone separate from overall** — mỗi tactic có `zone` riêng, overall computed từ aggregate.
- **Concept data từ refinement module** — `title`/`marketPositioning`/`pricing` từ Phase A confirmed concept.
- **Status `cancelled`/`paused`** — review vẫn trả data (frozen tại snapshot).
- **Total Votes selector** (MEMORY `project_total_votes_selector_pattern.md`) — `text=Total votes` chỉ match label, số nằm ở element riêng. Fix selectors trong `poll-result-card.component.ts:22` + L156/165.

## Testing methods

| Method                | Apply                                                                                                                       |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Decision table        | 4 zone classifications × tactic mix variants. Mỗi row = 1 test với mock metrics                                             |
| Boundary              | `totalReach`: 49, 50, 51 · `interestRate`: 9.9%, 10%, 19.9%, 20%                                                            |
| State transition      | Status: `running` → `completed` → `cancelled` (review still works)                                                          |
| Equivalence partition | Tactic mix combos (LP only · LP+poll · all 3)                                                                               |
| Security              | 401 unauth · cross-user campaignId/vId                                                                                      |
| UX/UI                 | Confidence label text (NOT color/legend) · empty state khi `null` zone · loading skeleton · tactic card render · responsive |

## Mock helpers cho zone test (fast path)

| Helper                       | Zone                                   | Cost  |
| ---------------------------- | -------------------------------------- | ----- |
| `createGreenZoneValidation`  | GREEN (50 reach / 10 interested = 20%) | ~1-2s |
| `createYellowZoneValidation` | YELLOW (100/15 = 15%)                  | ~1-2s |
| `createRedZoneValidation`    | RED (100/5 = 5%)                       | ~1-2s |
| `createNullZoneValidation`   | null (30/10 — reach<50)                | ~1-2s |

Dùng để test FE rendering + decision table mà không cần real public tracking.

## Project references

- [`docs/sprint_10/epic-03.2-poll-tactic/`](../../../sprint_10/epic-03.2-poll-tactic/) — review page integration với poll
- MEMORY `project_zone_confidence_mapping.md` — FE zone via confidence label, not color text
- MEMORY `project_total_votes_selector_pattern.md` — label vs number selector split
- `src/selectors/concept-validation.selectors.ts` — dashboard validation selectors
