# Phase B → Module: Validation Tactics

Chọn tactic mix (max 3) cho validation: `landing_page` · `youtube_poll` · `instagram_poll` · `email_survey` · `youtube_video_teaser` · `x_poll`. Mỗi tactic tạo 1 record với `tacticId` riêng → dùng cho tactic-specific setup downstream.

## Scope

| Field          | Value                                           |
| -------------- | ----------------------------------------------- |
| API base       | `/campaigns/:cId/validations/:vId/tactics`      |
| Required state | Phase B `status=draft`                          |
| Output         | `tactics: TacticItem[]` với `tacticId` per type |

## Upstream

| Cần                           | Nguồn                                                |
| ----------------------------- | ---------------------------------------------------- |
| `accessToken`                 | [`../../auth/signIn.md`](../../auth/signIn.md)       |
| `campaignId` + `validationId` | [Platform](./platform.md) (POST /validations đã tạo) |
| `tactics: TacticType[]`       | Module này                                           |

## Downstream (Tactics unlocks)

| Tactic type                                  | Module tiếp                                                 |
| -------------------------------------------- | ----------------------------------------------------------- |
| `landing_page`                               | [Landing Page](./landing-page.md) — generate LP + tracking  |
| `youtube_poll` / `instagram_poll` / `x_poll` | [Poll Tactics](./poll-tactics.md) — save poll URL + results |
| `email_survey`                               | [Email Survey](./email-survey.md) — recipients + content    |
| `youtube_video_teaser`                       | (no extra setup)                                            |

Mọi tactic → [Duration](./duration.md) → start validation.

## Endpoints

```
POST   .../tactics                    ← save tactic mix (replace all)
GET    .../tactics                    ← read selected tactics

# Sprint 12 — confirm-modal flow (Story 03.1.2)
POST   .../tactics/probe-change       ← preview impact của tactic change (data loss?)
POST   .../tactics/confirm-change     ← apply change sau khi user confirm
```

| Endpoint                            | Method         | Gate |
| ----------------------------------- | -------------- | ---- |
| `VALIDATION.tactics(cId, vId)` POST | 🔒 save mix    |
| `VALIDATION.tactics(cId, vId)` GET  | 📖 read        |
| `probe-change` / `confirm-change`   | 🔒 change flow |

## Service layer (`src/validation/tactics/`)

| Function                                                                         | Mục đích                                                               |
| -------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `saveTactics(request, accessToken, cId, vId, payload, testName)`                 | Save tactic mix                                                        |
| `getSelectedTactics(request, accessToken, cId, vId, testName)`                   | Read                                                                   |
| `probeTacticsChange` · `confirmTacticsChange`                                    | Modal Confirm flow (Sprint 12 Epic 03.1.2)                             |
| `saveTacticsWithoutAuth` · `*WithInvalidToken` · `*WithPayload` · `*WithRawBody` | Negative tests                                                         |
| `verifyTacticsResponseStructure` · `verifyTacticsMatch`                          | Assertions                                                             |
| Factory                                                                          | `tactics.factory.ts` → `createTacticsPayloadWith(types: TacticType[])` |

## Types (`src/validation/validation.types.ts`)

| Type               | Value                                                                                                              |
| ------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `TacticType`       | 6 members: `landing_page` · `youtube_poll` · `instagram_poll` · `email_survey` · `youtube_video_teaser` · `x_poll` |
| `ValidationTactic` | `{id, type, tacticType, reachCount, interestedCount, interestedRate, zone, isAutoTracked, trackingMethod, ...}`    |
| `TacticsPayload`   | `{tacticTypes: TacticType[]}` (+ optional `isForceDelete`)                                                         |

## Constraints

- **Max 3 tactics** per validation (BE enforce 400).
- **`landing_page` thường default** — luôn được include.
- **Replace semantics** — POST `/tactics` replace cả mix; reorder hoặc partial update không support thẳng — phải confirm-change flow.
- **Modal Confirm Tactics Change (Sprint 12)** — khi user đổi tactic mix sau khi đã có data (poll results, LP visits), BE yêu cầu `probe-change` rồi `confirm-change` với `isForceDelete=true` để confirm data loss.
- **TacticType strict** — local narrow types phải dùng `Extract<TacticType,'youtube_poll'|'instagram_poll'>` (MEMORY 2026-05-13).
- **Single-shot setup** — sau khi Phase B chuyển `running`, save lần 2 → `ERR_1001`.

## Testing methods

| Method                | Apply                                                                         |
| --------------------- | ----------------------------------------------------------------------------- |
| Equivalence partition | Valid mix (1-3 tactics) vs Invalid (>3, unknown type, empty)                  |
| Boundary              | `tactics.length`: 0, 1, 3, 4                                                  |
| State transition      | Modal Confirm flow: `probe → confirm → applied`, `probe → cancel → unchanged` |
| Decision table        | Force-delete scenarios: data exists Y/N × user confirms Y/N                   |
| Security              | 401/403 unauth · cross-user vId                                               |
