# Roadmap Docs — Index

Tài liệu reference cho **state machine** của campaign lifecycle. Mỗi phase doc mô tả:

- **State** — flag/status sau khi vào phase
- **Upstream** — deps cần thoả mãn để bước vào phase
- **Downstream** — phase nào được unlock + endpoint gate
- **Real flow** vs **Mock shortcut** (skip cost)
- **Service/Factory/Helper layer** — file:symbol map
- **Types** — type names + file location
- **Constraints** — failure log + BE quirks
- **Decision matrix** — khi nào dùng mock vs real
- **Endpoints reference**

## 📁 Folder layout

```
docs/roadmap/
├── README.md                  ← bạn đang ở đây (index dẫn đường)
├── auth/                      ← authentication gateway (precondition cho mọi thứ)
│   ├── signUp.md              ✅ Create account (POST /auth/signup, 201 no body)
│   └── signIn.md              ✅ Login + session/token mgmt (gateway cho mọi authenticated API)
└── campaign/                  ← campaign lifecycle state machine
    ├── phaseA.md              ✅ Concept Refinement (Q1-Q7 + mock)
    ├── phaseB.md              ✅ Validation — index + setup gate
    ├── phaseB/                ✅ Phase B sub-modules
    │   ├── platform.md             Step 1 — select 1-6 platforms
    │   ├── tactics.md              Step 2 — tactic mix (max 3)
    │   ├── landing-page.md         Step 3a — LP generate + public tracking
    │   ├── poll-tactics.md         Step 3b — poll URL + results (Story 03.2.4)
    │   ├── email-survey.md         Step 3c — recipients + content + analytics
    │   ├── duration.md             Step 4 — durationDays + /refining-completion
    │   └── dashboard-validation.md Step 5 — review + traffic light zone
    ├── phaseC.md              ⏳ TODO — Goal / Publish / LIVE
    └── phaseD.md              ⏳ TODO — Delivery / Refund / Escrow
```

Phạm vi: **state machine + service layer reference**. KHÔNG chứa story spec, test plan, hay API contract chi tiết — những thứ đó nằm ở feature folder (xem § "Cross-reference" bên dưới).

## 📖 Đọc theo thứ tự

**Auth là precondition tuyệt đối**: signUp → signIn rồi mới đến campaign Phase A → B → C → D. Mọi phase doc giả định bạn đã có `accessToken` từ signIn — upstream chain luôn dừng ở signIn (root).

## Auth Gateway

| Bước        | Doc                                  | Mô tả                                                                  | Trạng thái doc |
| ----------- | ------------------------------------ | ---------------------------------------------------------------------- | -------------- |
| **Sign Up** | [`auth/signUp.md`](./auth/signUp.md) | Create account (201, NO body — phải login riêng)                       | ✅ Done        |
| **Sign In** | [`auth/signIn.md`](./auth/signIn.md) | Login → `accessToken`/`refreshToken` → unlock TẤT CẢ authenticated API | ✅ Done        |

## Campaign Lifecycle

| Phase                    | Doc                                          | Mô tả                                                         | Trạng thái doc |
| ------------------------ | -------------------------------------------- | ------------------------------------------------------------- | -------------- |
| **A** Concept Refinement | [`campaign/phaseA.md`](./campaign/phaseA.md) | Q1-Q7 AI refinement → concept structured. Default = mock      | ✅ Done        |
| **B** Validation         | [`campaign/phaseB.md`](./campaign/phaseB.md) | Validate concept với tactics × platforms → traffic light zone | ✅ Done        |
| **C** Goal / Publish     | _(pending)_                                  | Goal setting, campaign page, publish → LIVE funding           | ⏳ TODO        |
| **D** Delivery           | _(pending)_                                  | Post-funding: delivery, refund, dispute, escrow               | ⏳ TODO        |

## 🎯 Quick-pick: hành động ↔ doc

| Bạn đang làm gì?                                                       | Đọc trước                                                                                                                                                  |
| ---------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Setup test cần fresh account (parallel-safe, data isolation)           | [signUp](./auth/signUp.md) § "Real flow" + [signIn](./auth/signIn.md) § "Real flow"                                                                        |
| Smoke / regression dùng shared TEST_USER từ `.env`                     | [signIn](./auth/signIn.md) § "Auth state cho CI / cross-test reuse"                                                                                        |
| Test lockout / rate limit / token expiry                               | [signIn](./auth/signIn.md) § "Constraints" + § "Khi nào dùng login fresh vs reuse"                                                                         |
| Test 401/403 unauth — fixture cookies leak vào test                    | [signIn](./auth/signIn.md) § "Constraints" — F-1 bonus (`request.newContext()`)                                                                            |
| Setup test cần campaign Phase B/C/D (không quan tâm concept)           | [phaseA](./campaign/phaseA.md) § "Mock shortcut" + § "Default policy"                                                                                      |
| Test Phase B validation flow (tactics / platforms / duration / launch) | [phaseB](./campaign/phaseB.md) § "Real flow" + [phaseA](./campaign/phaseA.md) § "Mock shortcut"                                                            |
| Test traffic light zone (GREEN/YELLOW/RED)                             | [phaseB](./campaign/phaseB.md) § "Mock shortcut" — 4 zone preset helpers                                                                                   |
| Test E2E Golden Flow (signature test cho release)                      | [signUp](./auth/signUp.md) → [signIn](./auth/signIn.md) → [phaseA](./campaign/phaseA.md) § "Default policy" → [phaseB](./campaign/phaseB.md) § "Real flow" |
| Tạo new feature ở Phase X — không biết bắt đầu đâu                     | Doc Phase X § "Upstream" → đệ quy upstream → § "Service layer" → § "Endpoints reference"                                                                   |
| Test fail kỳ lạ sau seed                                               | Doc Phase X § "Constraints" (failure log + BE quirks)                                                                                                      |
| Cần biết gọi service/helper nào                                        | Doc Phase X § "Service / Factory / Helper layer"                                                                                                           |
| Migrate test từ direct `request.post` → service                        | Doc Phase X § "Endpoints reference" + § "Service layer"                                                                                                    |

## 🧭 Doc convention

- **File path** trong doc dùng absolute từ project root (`src/...`).
- **Endpoints** ghi theo format `METHOD /path` + `API_ENDPOINTS.X.Y(id)` reference.
- **Failure log links** dùng tag `F-N` từ `CLAUDE.md` (vd `F-1` = "no direct request.post").
- **MEMORY citations** ghi date `YYYY-MM-DD` để future-reader judge staleness.
- **Cost** ghi giây/phút thực tế observed trên STG.
- **Decision matrix** luôn có cột "Cost" — giúp pick path cheapest cho use-case.

## 🔗 Cross-reference với phần còn lại của `docs/`

Phase doc chỉ nói **lifecycle + service layer**. Feature/story spec, API contract chi tiết, bug tracker → tra ở folder feature tương ứng:

### Theo lifecycle phase

| Phase                       | Feature folder liên quan                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Auth** Sign Up / Sign In  | [`docs/api/`](../api/) (auth-api-contract) · [`docs/sign-in-with-social/`](../sign-in-with-social/) · [`docs/password-reset/`](../password-reset/) · [`docs/manage-my-profile/`](../manage-my-profile/) (email verification, profile mgmt)                                                                                                                                                                                                                                                   |
| **A** Concept               | [`docs/sprint2/squad-idea/`](../sprint2/squad-idea/) (Q1-Q7 refinement, story 02.x) · [`docs/sprint2/squad-coca/phaseA-data-auto-population/`](../sprint2/squad-coca/)                                                                                                                                                                                                                                                                                                                       |
| **B** Validation            | [`docs/sprint_9/epic-03.7-email-survey/`](../sprint_9/epic-03.7-email-survey/) · [`docs/sprint_10/epic-03.2-poll-tactic/`](../sprint_10/epic-03.2-poll-tactic/) · [`docs/sprint_12/epic-03.1.2-modal-confirm-tactics-change/`](../sprint_12/epic-03.1.2-modal-confirm-tactics-change/) · [`docs/utm-visit-tracking/`](../utm-visit-tracking/) · [`docs/hero-media-upload/`](../hero-media-upload/) · [`docs/landing-page-editor/`](../landing-page-editor/) · [`docs/reviews/`](../reviews/) |
| **B → C transition**        | [`docs/transition-to-phase-C/`](../transition-to-phase-C/)                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| **C** Goal/Publish          | [`docs/goal/`](../goal/) · [`docs/campaign-editor/`](../campaign-editor/) · [`docs/hero-media-upload/`](../hero-media-upload/) (Phase C) · [`docs/campaign-q-and-a/`](../campaign-q-and-a/) · [`docs/discovery-campaign/`](../discovery-campaign/) · [`docs/Epic-07.3-campaign-detail-evaluation/`](../Epic-07.3-campaign-detail-evaluation/) · [`docs/campaign-process-update/`](../campaign-process-update/)                                                                               |
| **C** Checkout/Pledge       | [`docs/checkout/`](../checkout/)                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| **D** Delivery/Refund       | [`docs/delivery-campaings-dashboard/`](../delivery-campaings-dashboard/) · [`docs/campaign-escrow-setup/`](../campaign-escrow-setup/) · [`docs/withdrawal/`](../withdrawal/)                                                                                                                                                                                                                                                                                                                 |
| **Dashboard (cross-phase)** | [`docs/campaign-dashboard/`](../campaign-dashboard/) · [`docs/sprint_11/epic-09/`](../sprint_11/epic-09/) · [`docs/sprint_12/creator-dashboard/`](../sprint_12/creator-dashboard/)                                                                                                                                                                                                                                                                                                           |

### Theo loại tài liệu

| Tài liệu                                                       | Folder                                                                                                                                          |
| -------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| API contracts (auth, campaigns-list, validation, review, etc.) | [`docs/api/`](../api/)                                                                                                                          |
| Story specs + dev-stories + test-plans (per sprint)            | [`docs/sprint_9/`](../sprint_9/) · [`docs/sprint_10/`](../sprint_10/) · [`docs/sprint_11/`](../sprint_11/) · [`docs/sprint_12/`](../sprint_12/) |
| E2E test design + scenarios                                    | [`docs/e2e/`](../e2e/) · [`docs/story-e2e/`](../story-e2e/) · feature folder `*/test-design/`                                                   |
| User-facing guides                                             | [`docs/living-docs/user-guide/`](../living-docs/user-guide/)                                                                                    |
| Report Portal + test reports                                   | [`docs/report-portal/`](../report-portal/) · [`docs/reports/`](../reports/)                                                                     |
| Templates (story, dev-story, test-plan)                        | [`docs/templates/`](../templates/)                                                                                                              |

### Theo feature (alphabetical)

| Feature                         | Path                                                                                                     |
| ------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Campaign Dashboard (creator)    | [`docs/campaign-dashboard/`](../campaign-dashboard/)                                                     |
| Campaign Editor                 | [`docs/campaign-editor/`](../campaign-editor/)                                                           |
| Campaign Escrow Setup           | [`docs/campaign-escrow-setup/`](../campaign-escrow-setup/)                                               |
| Campaign Process Update         | [`docs/campaign-process-update/`](../campaign-process-update/)                                           |
| Campaign Q&A                    | [`docs/campaign-q-and-a/`](../campaign-q-and-a/)                                                         |
| Checkout                        | [`docs/checkout/`](../checkout/)                                                                         |
| Delivery Campaigns Dashboard    | [`docs/delivery-campaings-dashboard/`](../delivery-campaings-dashboard/)                                 |
| Discovery Campaign              | [`docs/discovery-campaign/`](../discovery-campaign/)                                                     |
| Email Capture (double opt-in)   | [`docs/squad coca/email-capture-with-double-opt-in/`](../squad%20coca/email-capture-with-double-opt-in/) |
| Goal Setting                    | [`docs/goal/`](../goal/)                                                                                 |
| Header Navigation               | [`docs/header-navigation/`](../header-navigation/)                                                       |
| Hero Media Upload (Phase B + C) | [`docs/hero-media-upload/`](../hero-media-upload/)                                                       |
| Landing Page Editor             | [`docs/landing-page-editor/`](../landing-page-editor/)                                                   |
| Manage My Profile               | [`docs/manage-my-profile/`](../manage-my-profile/)                                                       |
| Password Reset                  | [`docs/password-reset/`](../password-reset/)                                                             |
| Reviews                         | [`docs/reviews/`](../reviews/)                                                                           |
| Sign-in with Social             | [`docs/sign-in-with-social/`](../sign-in-with-social/)                                                   |
| Transition to Phase C           | [`docs/transition-to-phase-C/`](../transition-to-phase-C/)                                               |
| UTM Visit Tracking              | [`docs/utm-visit-tracking/`](../utm-visit-tracking/)                                                     |
| Withdrawal                      | [`docs/withdrawal/`](../withdrawal/)                                                                     |

## 📌 Related references (root-level)

| File                                                                        | Mục đích                                                                 |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| [`/CLAUDE.md`](../../CLAUDE.md)                                             | Failure log (5 rules F-1..F-6 + hook layer) — đọc trước mọi session      |
| [`/MEMORY.md`](../../MEMORY.md)                                             | Sprint state hiện tại + bugs đang mở (live, update mỗi sprint)           |
| [`/_bmad-output/project-context.md`](../../_bmad-output/project-context.md) | Anti-patterns + security testing reference                               |
| [`/_bmad-output/`](../../_bmad-output/)                                     | BMAD agent outputs (code reviews, retros, planning artifacts)            |
| [`/.claude/hooks/`](../../.claude/hooks/)                                   | Layer-1 enforcement hooks (anti-pattern guards, test verification gates) |
