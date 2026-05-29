# Phase B → Module: Platform Selection

Bước **đầu tiên** của Phase B: chọn 1-6 platforms mà creator muốn validate trên (`YOUTUBE`, `FACEBOOK`, `INSTAGRAM`, `EMAIL`, `X`, `TIKTOK`). Việc gọi `POST /campaigns/:cId/validations` cũng đồng thời **khởi tạo validation record** → từ đây Phase B chuyển khỏi `draft` ngay khi setup endpoints khác được gọi.

## Scope

| Field          | Value                                                                                |
| -------------- | ------------------------------------------------------------------------------------ |
| API base       | `/campaigns/:cId/validations`                                                        |
| Required state | Phase B `status=draft` (fresh campaign) — xem [phaseB §Setup API gate](../phaseB.md) |
| Output         | `validationId`                                                                       |

## Upstream

| Cần                     | Nguồn                                                |
| ----------------------- | ---------------------------------------------------- |
| `accessToken`           | [`../../auth/signIn.md`](../../auth/signIn.md)       |
| `campaignId`            | [phaseA Mock shortcut](../phaseA.md) hoặc real flow  |
| `platforms: Platform[]` | Constants `VALID_PLATFORMS` từ `validation.types.ts` |

## Downstream (Platform unlocks)

| Module tiếp                                                                                               | Mục đích                                 |
| --------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| [Validation Tactics](./tactics.md)                                                                        | Save tactic mix cho validationId vừa tạo |
| [Select Duration](./duration.md)                                                                          | Set durationDays                         |
| [Landing Page](./landing-page.md) / [Poll Tactics](./poll-tactics.md) / [Email Survey](./email-survey.md) | Setup tactic-specific data               |

## Endpoints

```
POST   /campaigns/:cId/validations            ← create validation + save platforms
GET    /campaigns/:cId/validations/:vId/platforms   ← read selected platforms
```

🔒 = setup gate (`status=draft` only).

| Endpoint                            | Method | Gate                       |
| ----------------------------------- | ------ | -------------------------- |
| `VALIDATION.getBase(cId)`           | POST   | 🔒 create + save platforms |
| `VALIDATION.getPlatforms(cId, vId)` | GET    | 📖 read                    |

## Service layer (`src/validation/platform/`)

| Function                 | File · Symbol                                                                                     |
| ------------------------ | ------------------------------------------------------------------------------------------------- |
| Save platforms (auth)    | `platform.service.ts` → `saveValidation(request, campaignId, accessToken, platforms[], testName)` |
| Save with custom payload | `platform.service.ts` → `saveValidationWithPayload` (negative test)                               |
| Save WITHOUT auth        | `platform.service.ts` → `saveValidationWithoutAuth` (401 test)                                    |
| Save with invalid token  | `platform.service.ts` → `saveValidationWithInvalidToken` (401 test)                               |
| GET selected             | `platform.service.ts` → `getSelectedPlatforms` · `*WithoutAuth` · `*WithInvalidToken`             |
| Verifiers                | `verifyValidationResponseStructure` · `verifyValidPlatforms` · `verifyPlatformsMatch`             |
| Factory                  | `platform.factory.ts`                                                                             |

Service `validation.service.ts` → `createValidation` cũng có sẵn — thường dùng cho test setup nhanh (default platforms `['YOUTUBE','INSTAGRAM']`).

## Types (`src/validation/validation.types.ts`)

| Type                         | Value                                                                |
| ---------------------------- | -------------------------------------------------------------------- |
| `Platform`                   | `'YOUTUBE'\|'FACEBOOK'\|'INSTAGRAM'\|'EMAIL'\|'X'\|'TIKTOK'`         |
| `VALID_PLATFORMS`            | Readonly array 6 platforms                                           |
| `INVALID_PLATFORMS`          | `['TWITTER','LINKEDIN','SNAPCHAT','PINTEREST']` (negative test data) |
| `CASE_SENSITIVITY_PLATFORMS` | `['youtube','Youtube','FaceBook']` (case test)                       |
| `CreateValidationPayload`    | `{platforms: Platform[]}`                                            |
| `ValidationResponse`         | `{id, campaignId, selectedPlatforms, createdAt, updatedAt}`          |
| `SelectedPlatformsResponse`  | `{platforms: Platform[]}`                                            |
| `VALIDATION_CONSTRAINTS`     | `{MIN_PLATFORMS:1, MAX_PLATFORMS:6}`                                 |

## Constraints

- **Platform case-sensitive** — `youtube`/`Youtube`/`FaceBook` → 400. UPPERCASE chính xác.
- **`TWITTER` legacy** — rebrand → `X`. Submit `TWITTER` → 400.
- **Platforms count** — MIN 1, MAX 6. Empty array `[]` → 400 "At least one platform must be selected". 7+ → 400.
- **Invalid enum** — `LINKEDIN`/`SNAPCHAT`/`PINTEREST` → 400.
- **Single-shot** — sau `saveValidation` Phase B chuyển khỏi `draft` → call 2 → `ERR_1001`.

## Testing methods để cover (xem [skill.md](../../../qa-test-case/skill.md))

| Method                | Apply                                                                              |
| --------------------- | ---------------------------------------------------------------------------------- |
| Boundary              | `platforms.length`: 0, 1, 2, 5, 6, 7                                               |
| Equivalence partition | Valid (6 platforms) vs Invalid (TWITTER, lowercase, unsupported)                   |
| Security              | 401 (no auth) · 401 (invalid token) — `*WithoutAuth` / `*WithInvalidToken` helpers |
