# Phase B — Validation (Review & Validate Campaign)

Creator validate concept với target audience qua tactics (landing page / poll / email survey) trên platforms (YouTube / Instagram / FB / X / TikTok / Email). Output: traffic light zone (GREEN/YELLOW/RED) + analytics (reach, interested, interest rate) cho mỗi tactic → input cho Phase C goal setting.

## 📂 Sub-modules

Phase B chia thành 7 module độc lập theo flow setup → start → review. Mỗi module có doc riêng với State / Upstream / Endpoints / Service / Constraints / Testing methods.

```
docs/roadmap/campaign/phaseB/
├── platform.md              ← Step 1: chọn 1-6 platforms (tạo validationId)
├── tactics.md               ← Step 2: chọn tactic mix (max 3) — generate tacticIds
├── landing-page.md          ← Step 3a (tactic=landing_page): generate LP + public tracking
├── poll-tactics.md          ← Step 3b (tactic=youtube/instagram/x_poll): save URL + results
├── email-survey.md          ← Step 3c (tactic=email_survey): recipients + content + analytics
├── duration.md              ← Step 4-5: set durationDays + POST /refining-completion (draft→running)
└── dashboard-validation.md  ← Review: traffic light zone classification (read-only)
```

| Order | Module                                                   | Trigger                                                                  |
| ----- | -------------------------------------------------------- | ------------------------------------------------------------------------ |
| 1     | [Platform](./phaseB/platform.md)                         | Create validation + chọn platforms                                       |
| 2     | [Validation Tactics](./phaseB/tactics.md)                | Save tactic mix → có `tacticId` per type                                 |
| 3a    | [Landing Page](./phaseB/landing-page.md)                 | Generate LP nếu `landing_page` trong mix                                 |
| 3b    | [Poll Tactics](./phaseB/poll-tactics.md)                 | Save poll URL nếu `youtube_poll`/`instagram_poll`/`x_poll` trong mix     |
| 3c    | [Email Survey](./phaseB/email-survey.md)                 | Setup content + recipients nếu `email_survey` trong mix                  |
| 4     | [Select Duration](./phaseB/duration.md)                  | PATCH duration + POST `/refining-completion` (one-way `draft → running`) |
| 5     | [Dashboard Validation](./phaseB/dashboard-validation.md) | Review aggregate → traffic light zone → decide Phase C                   |

⚠️ **Steps 1-4 chỉ chạy khi Phase B `status=draft`** — xem § "Setup API gate" dưới đây.

## State

| Field               | Value                                                               |
| ------------------- | ------------------------------------------------------------------- | -------- | ----- | --------------------------- |
| `currentPhase`      | `PHASE_B`                                                           |
| `operationalStatus` | `IN_PROGRESS`                                                       |
| Validation `status` | `draft` → `running` → `completed` (`cancelled` · `paused` possible) |
| Result              | `trafficLightZone: 'GREEN'                                          | 'YELLOW' | 'RED' | null` (null nếu reach < 50) |

## ⚠️ Setup API gate — `status=draft` ONLY

> **TẤT CẢ setup APIs của Phase B chỉ hoạt động khi validation `status=draft`.**
> Sau khi `POST /refining-completion` được gọi → `status: draft → running` → mọi setup API dưới đây trả lỗi (typically `400`/`409` với `ERR_1001 "Invalid phase transition"`).
> KHÔNG có endpoint nào reset từ `running`/`completed` về `draft`. Để re-test → seed campaign mới từ Phase A.

| Endpoint                                                          | Required `status`                           | Lỗi khi sai state                                              |
| ----------------------------------------------------------------- | ------------------------------------------- | -------------------------------------------------------------- |
| `POST /campaigns/:cId/validations` (create validation)            | `draft` (fresh campaign, Phase B chưa init) | `ERR_1001` — `CampaignService.markStartPhaseB` reject 2nd call |
| `POST /campaigns/:cId/validations/:vId/tactics` (save tactic mix) | `draft`                                     | BE reject — tactics frozen sau khi running                     |
| `POST .../tactics/:tId/landing-pages` (generate LP)               | `draft`                                     | BE reject                                                      |
| `PATCH .../tactics/:tId {pollUrl}` (save poll URL)                | `draft`                                     | BE reject                                                      |
| `POST .../tactics/:tId/email-survey/email-list` (recipients)      | `draft`                                     | BE reject — list locked sau khi gửi                            |
| `POST .../tactics/:tId/email-survey/content` (content)            | `draft`                                     | BE reject                                                      |
| `PATCH /campaigns/:cId/validations/:vId {durationDays}`           | `draft`                                     | BE reject — duration locked sau start                          |
| `POST /mock/validations` (mock shortcut)                          | `draft` (single-shot)                       | `ERR_1001`                                                     |
| `POST .../validations/:vId/refining-completion` (start)           | `draft` (chính nó transition state)         | Idempotent block sau call đầu                                  |

**Hệ quả test design:** mỗi test case cần fresh Phase B setup → mỗi test phải `createMockCampaign` (Phase A) mới rồi mới chạy setup. Reusing `TEST_USER1..10` campaigns sẵn có sẽ fail nếu campaign đó đã transition Phase B.

**Còn dùng được sau `status=running`:**

- `GET .../validations/:vId` · `GET .../platforms` · `GET .../tactics` · `GET .../review` (read-only)
- `POST .../tactics/:tId/results` (submit poll results — Story 03.2.4)
- `POST .../tactics/:tId/reminder` · `GET .../reminder`
- `POST /public/landing-pages/:shortId/visit` · `/subscribe` (public, no auth)

## Upstream (deps để vào Phase B)

| Cần                        | Nguồn               | Note                                                                                                                                                                                            |
| -------------------------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `accessToken`              | Phase A auth        | Bearer token                                                                                                                                                                                    |
| `campaignId`               | Phase A output      | `currentPhase=PHASE_A`, concept đã có (concept data hoặc mock campaign)                                                                                                                         |
| **Phase B `status=draft`** | Fresh campaign only | Xem § "Setup API gate" — TẤT CẢ setup APIs phụ thuộc state này. Sau lần đầu `createValidation` hoặc `createMockValidation`, state chuyển khỏi `draft` → không quay lại được (MEMORY 2026-05-15) |

## Downstream (Phase B unlocks)

| Phase tiếp            | Endpoint gate                                | Điều kiện                                                                                  |
| --------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------ |
| **C** goal/refinement | `POST /campaigns/:id/goals/start-refinement` | Phase B `status=completed` (cần `/refining-completion` hoặc mock với `status='completed'`) |

## Real flow (production path, ~5-10s setup + duration days runtime)

Steps **1-4** (setup) yêu cầu `status=draft` — xem § "Setup API gate". Step 5 là điểm chuyển trạng thái không thể đảo ngược.

| #   | Endpoint                                                                      | Required state          | Out / Note                                                                                |
| --- | ----------------------------------------------------------------------------- | ----------------------- | ----------------------------------------------------------------------------------------- |
| 1   | `POST /campaigns/:cId/validations {platforms:[YOUTUBE,INSTAGRAM,...]}`        | `draft`                 | `validationId`. 1-6 platforms, case-sensitive (`TWITTER` rejected → dùng `X`)             |
| 2   | `POST /campaigns/:cId/validations/:vId/tactics {tacticTypes:[...]}`           | `draft`                 | Save tactic mix. Max 3 tactics. `landing_page` thường là default                          |
| 3a  | `POST .../tactics/:tId/landing-pages` (landing_page)                          | `draft`                 | Generate LP, returns `landingPageShortId`                                                 |
| 3b  | `POST .../tactics/:tId/email-survey/email-list {emails:[...]}` (email_survey) | `draft`                 | Ít nhất 1 recipient để start-validation pass                                              |
| 3c  | `PATCH .../tactics/:tId {pollUrl}` (youtube/instagram/x_poll)                 | `draft`                 | Save real poll URL                                                                        |
| 4   | `PATCH /campaigns/:cId/validations/:vId {durationDays}`                       | `draft`                 | 3-14 days                                                                                 |
| 5   | `POST .../validations/:vId/refining-completion`                               | `draft` → `running`     | **One-way transition** — sau bước này KHÔNG còn setup được. Validation chính thức bắt đầu |
| 6   | (Wait duration_days or manual end)                                            | `running` → `completed` | BE auto-transition sau khi hết duration                                                   |
| 7   | `GET .../validations/:vId/review`                                             | any (read-only)         | Review data: traffic light + tactics analytics + concept                                  |

## Mock shortcut (skip waiting + tracking, ~1-2s)

| Endpoint                 | Payload                                                     | Effect        | Constraint                                                                                                   |
| ------------------------ | ----------------------------------------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `POST /mock/validations` | `{campaignId, totalViews, totalInterested, status:'running' | 'completed'}` | Tạo validation với LP tactic + metrics có sẵn (`reachCount`, `interestedCount`). Bypass tracking dedup-by-IP | **Setup gate** — Phase B `status=draft` only. Single-shot per campaign. Sau call → state khỏi `draft`, mock không usable nữa. KHÔNG trigger activity events vào `/dashboard/activity` (MEMORY 2026-05-15) |

Zone preset helpers:

| Helper                       | `totalViews` / `totalInterested` | Zone                             |
| ---------------------------- | -------------------------------- | -------------------------------- |
| `createGreenZoneValidation`  | 50 / 10 (20%)                    | GREEN (rate ≥ 20%, reach ≥ 50)   |
| `createYellowZoneValidation` | 100 / 15 (15%)                   | YELLOW (rate 10-19%, reach ≥ 50) |
| `createRedZoneValidation`    | 100 / 5 (5%)                     | RED (rate < 10%, reach ≥ 50)     |
| `createNullZoneValidation`   | 30 / 10 (33% but <50 reach)      | `null` (insufficient data)       |

## Service / Factory / Helper layer

| Layer                | File · Symbol                                                                                                                                                                                                            |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Service real         | `src/validation/validation.service.ts` → `createValidation` · `getValidationById` · `setupTestContext`                                                                                                                   |
| Service mock         | `src/validation/mock-validation.service.ts` → `createMockValidation` · `createGreen/Yellow/Red/NullZoneValidation`                                                                                                       |
| Service tactics      | `src/validation/tactics/tactics.service.ts` → `saveTactics` · `getSelectedTactics`                                                                                                                                       |
| Service duration     | `src/validation/duration/duration.service.ts` → `updateDuration` · `startValidation` (POST `/refining-completion`)                                                                                                       |
| Service landing page | `src/validation/landing-page/landing-page.service.ts` → `generateLandingPage`                                                                                                                                            |
| Service email survey | `src/validation/email-survey/email-survey.service.ts` → `saveEmailList` · `saveContent`                                                                                                                                  |
| Service poll         | `src/poll-tactic/*` → `savePollUrl` · `submitPollResults` · `getTacticDetails`                                                                                                                                           |
| Service review       | `src/validation/review/review.service.ts` → review endpoint                                                                                                                                                              |
| Service platform     | `src/validation/platform/*` → platform CRUD                                                                                                                                                                              |
| Factory tactics      | `src/validation/tactics/tactics.factory.ts` → `createTacticsPayloadWith(types)`                                                                                                                                          |
| Factory platform     | `src/validation/platform/platform.factory.ts`                                                                                                                                                                            |
| E2E helper           | `src/helpers/phase-b-navigation.helper.ts`                                                                                                                                                                               |
| Fixture              | `src/fixtures/validation.fixture.ts` · `src/fixtures/e2e-landing-page.fixture.ts` · `src/fixtures/e2e-email-survey.fixture.ts` · `src/fixtures/e2e-review.fixture.ts` · `src/fixtures/e2e-hero-media-phase-b.fixture.ts` |

## Types (`src/validation/validation.types.ts`)

| Type                                                                        | Mô tả                                                                                                              |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `Platform = 'YOUTUBE'\|'FACEBOOK'\|'INSTAGRAM'\|'EMAIL'\|'X'\|'TIKTOK'`     | ⚠️ `TWITTER` invalid (rebrand → `X`)                                                                               |
| `TacticType`                                                                | 6 members: `landing_page` · `youtube_poll` · `instagram_poll` · `email_survey` · `youtube_video_teaser` · `x_poll` |
| `ValidationStatus = 'draft'\|'running'\|'completed'\|'cancelled'\|'paused'` | Phase B state machine                                                                                              |
| `TrafficLightZone = 'GREEN'\|'YELLOW'\|'RED'`                               | Zone classification (null nếu reach<50)                                                                            |
| `DURATION_DAYS = {MIN:3, MAX:14}`                                           | Validation runtime constraint                                                                                      |
| `VALIDATION_CONSTRAINTS = {MIN_PLATFORMS:1, MAX_PLATFORMS:6}`               |                                                                                                                    |
| `GetValidationResponse` · `ValidationReviewResponseDto` · `ReviewTactic`    | Response shapes (camelCase, **không** snake_case như API docs)                                                     |

## Mocks available

| Mock                    | Endpoint                 | Effect                                                                               |
| ----------------------- | ------------------------ | ------------------------------------------------------------------------------------ |
| Validation with metrics | `POST /mock/validations` | Skip tracking, set `reachCount`/`interestedCount` directly. Single-shot per campaign |

⚠️ `POST /mock/validations/poll` (legacy) — KHÔNG dùng. Real-flow `createValidation + saveTactics + updateDuration + startValidation` mới đủ trigger BE state machine cho Phase B tasks/events (MEMORY 2026-05-20).

## Constraints (failure log)

- **F-1** — KHÔNG `request.post()` thẳng vào endpoint validation. Đi qua service layer.
- **F-3** — Sau `createMockValidation` `status='completed'`, KHÔNG yield ngay nếu downstream check zone — probe `GET /validations/:vId` xác minh `trafficLightZone` populated.
- **BE-CONSTRAINT-001** (setup gate) — **TẤT CẢ setup APIs** (`POST /validations` · `POST .../tactics` · `POST .../landing-pages` · `PATCH .../tactics/:tId` (poll URL) · `POST .../email-survey/email-list` · `POST .../email-survey/content` · `PATCH .../validations/:vId` (duration) · `POST /mock/validations` · `POST .../refining-completion`) chỉ usable khi Phase B `status=draft`. Sau bất kỳ setup call thành công + `refining-completion` → state chuyển khỏi `draft`, KHÔNG quay lại được. Call setup lần 2 → `ERR_1001 "Invalid phase transition"` (`CampaignService.markStartPhaseB`). **Mỗi test case cần fresh Phase B → phải `createMockCampaign` mới** (MEMORY 2026-05-15). Xem § "Setup API gate" cho full danh sách.
- **BE-FINDING-002** — `POST /mock/validations` (any status) KHÔNG trigger activity events vào `/dashboard/activity` feed. Phase B events (B-EVT-02/04) cần real backer interaction qua public landing page submit hoặc BE expose dedicated mock endpoint (chưa có per 2026-05-18).
- Platform case-sensitive: `youtube`/`Youtube`/`FaceBook` → 400. Phải UPPERCASE chính xác.
- Platform `TWITTER` legacy → 400. Dùng `X`.
- Max 3 tactics per validation (BE enforce).
- `email_survey` cần ≥1 recipient trước `startValidation` (BE 400 nếu empty).
- Traffic light null khi reach < 50 (insufficient data threshold).
- Duration days 3-14 (outside → 400).
- Platforms 1-6 (outside → 400).

## Khi nào dùng mock vs real?

| Use-case                                                                   | Dùng                                                                            | Cost                                 |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ------------------------------------ |
| Test Phase C/D flow, validation results không quan trọng                   | `createMockValidation` `status='completed'`                                     | ~1-2s                                |
| Test traffic light zone classification (GREEN/YELLOW/RED/null)             | `createGreen/Yellow/Red/NullZoneValidation`                                     | ~1-2s                                |
| Test Phase B UI flow (platform select / tactics / duration / launch modal) | Real flow: `createValidation + saveTactics + ... + startValidation`             | ~5-10s                               |
| Test public landing page tracking (visits + email capture + UTM)           | Real flow + public endpoint hits (no mock)                                      | Variable                             |
| Test Phase B activity events (B-EVT-02/04)                                 | Real backer interaction qua public LP                                           | ⚠️ BE-FINDING-002: chưa có mock path |
| Test Phase C task emission từ Phase B→C transition (e.g. C-01)             | Real `createValidation + ... + /refining-completion` rồi gọi `start-refinement` | MEMORY 2026-05-20                    |

## Endpoints reference (`src/constants/api.constants.ts`)

Marker: 🔒 = **setup gate** (`status=draft` only) · 📖 = read-only (any state) · 🔄 = state-changing · ⚡ = runtime (`running`+).

```
# Validation lifecycle
VALIDATION.getBase(cId)                      POST  /campaigns/:cId/validations                  🔒 create
VALIDATION.getById(cId, vId)                 GET   /campaigns/:cId/validations/:vId             📖
VALIDATION.getPlatforms(cId, vId)            GET   .../platforms                                 📖
VALIDATION.tactics(cId, vId)                 POST  .../tactics                                   🔒 save tactic mix
                                             GET   .../tactics                                   📖 read

# Duration + start
VALIDATION.updateDuration(cId, vId)          PATCH .../validations/:vId                          🔒 duration days
VALIDATION.refiningCompletion(cId, vId)      POST  .../validations/:vId/refining-completion     🔄 draft → running (one-way)

# Review
VALIDATION.review(cId, vId)                  GET   .../validations/:vId/review                  📖 Phase B→C gate read

# Tactic-specific
.../tactics/:tId/landing-pages               POST  generate LP                                   🔒
                                             GET   read LP                                       📖
                                             PATCH update LP                                     🔒
.../tactics/:tId/poll-content                GET   generate poll                                 📖
.../tactics/:tId                             PATCH save poll URL                                 🔒
.../tactics/:tId/results                     POST  submit poll results                           ⚡ (after running)
                                             GET   read results                                  📖
.../tactics/:tId/email-survey/email-list     POST  save recipients                               🔒
                                             GET   read recipients                               📖
.../tactics/:tId/email-survey/content        POST  save content                                  🔒
                                             GET   read content                                  📖
.../tactics/:tId/reminder                    POST/GET reminder                                   ⚡

# Mock
REFINEMENT.MOCK.VALIDATIONS                  POST  /mock/validations                             🔒 single-shot per campaign

# Phase B → C gate
CAMPAIGN_GOALS.START_REFINEMENT(cId)         POST  /campaigns/:cId/goals/start-refinement       (requires Phase B status=completed)
```
