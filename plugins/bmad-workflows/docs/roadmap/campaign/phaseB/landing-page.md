# Phase B → Module: Landing Page

Generate landing page (LP) cho tactic `landing_page`. LP có public URL (`landingPageShortId`) cho audience visit → tracking `reachCount` + email capture cho `interestedCount`. Đầu vào của traffic light zone classification.

## Scope

| Field          | Value                                                                      |
| -------------- | -------------------------------------------------------------------------- |
| API base       | `/campaigns/:cId/validations/:vId/tactics/:tId/landing-pages`              |
| Public base    | `/public/landing-pages/:shortId`                                           |
| Required state | Phase B `status=draft` (creator side) · public endpoints work bất kỳ state |
| Output         | `landingPageShortId` (public URL), `landingPageId`                         |

## Upstream

| Cần                                                              | Nguồn                                                                              |
| ---------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `accessToken`                                                    | [`../../auth/signIn.md`](../../auth/signIn.md)                                     |
| `campaignId` + `validationId` + `tacticId` (type=`landing_page`) | [Tactics](./tactics.md) đã save `landing_page` trong mix                           |
| Concept data                                                     | [phaseA](../phaseA.md) — LP auto-populate từ concept (title, positioning, pricing) |

## Downstream

| Bước tiếp                                         | Mục đích                                                                     |
| ------------------------------------------------- | ---------------------------------------------------------------------------- |
| [Duration](./duration.md) + start validation      | `landing_page` cần generated trước khi start                                 |
| Public LP visit tracking                          | `POST /public/landing-pages/:shortId/visit` (audience side)                  |
| Email capture                                     | `POST /public/landing-pages/:shortId/subscribe` (audience side, opt-in flow) |
| [Dashboard Validation](./dashboard-validation.md) | LP reach + interest rate đóng góp vào traffic light zone                     |

## Endpoints

```
# Creator (auth)
POST   .../tactics/:tId/landing-pages          ← generate
GET    .../tactics/:tId/landing-pages          ← read
PATCH  .../tactics/:tId/landing-pages          ← update content

# Analytics (auth)
GET    .../tactics/:tId/landing-pages/analytics                  ← dashboard
GET    .../tactics/:tId/landing-pages/analytics/signups          ← paginated signups
GET    .../tactics/:tId/landing-pages/analytics/export-signups   ← CSV export

# Public (no auth)
POST   /public/landing-pages/:shortId/visit       ← track visit (UTM source)
POST   /public/landing-pages/:shortId/subscribe   ← email capture (double opt-in)
```

| Endpoint               | Method                                                    | Gate |
| ---------------------- | --------------------------------------------------------- | ---- |
| Creator POST/PATCH     | 🔒 setup                                                  |
| Creator GET            | 📖 read                                                   |
| Public visit/subscribe | ⚡ runtime — chạy được sau khi LP generated, bất kỳ state |

## Service layer

### Creator side (`src/validation/landing-page/landing-page.service.ts`)

| Function                                                                                        | Mục đích                                                                                                |
| ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `generateLandingPage(request, accessToken, cId, vId, tId, testName, expectedStatus?)`           | POST — generate                                                                                         |
| `getLandingPage` · `updateLandingPage`                                                          | Read + update                                                                                           |
| `generateLandingPageWithoutAuth` · `getLandingPageWithoutAuth` · `updateLandingPageWithoutAuth` | 401 tests                                                                                               |
| `createLandingPageSessionSetup`                                                                 | Full setup helper (Phase A+B fresh)                                                                     |
| Verifiers                                                                                       | `verifyShortIdFormat` · `verifySlugFormat` · `verifyRequiredPropsFields` · `verifyLandingPageStructure` |

### Public side (`src/validation/landing-page/landing-page-public.service.ts`)

| Function                                                | Mục đích                                                             |
| ------------------------------------------------------- | -------------------------------------------------------------------- |
| `trackVisit(request, shortId, payload, testName)`       | POST visit — UTM tracking                                            |
| `trackMultipleVisits`                                   | Burst visits cho zone-threshold tests                                |
| `subscribe(request, shortId, email, payload, testName)` | Email capture (double opt-in)                                        |
| `subscribeMultiple`                                     | Burst signups                                                        |
| `setupTrafficLightMetrics`                              | Helper: generate exact reach/interested để hit GREEN/YELLOW/RED zone |

## Types (`src/validation/landing-page/landing-page.types.ts`)

| Type                  | Note                                                                                       |
| --------------------- | ------------------------------------------------------------------------------------------ |
| `LandingPageResponse` | `{id, shortId, slug, props:{...}, ...}` — props chứa title/positioning/pricing từ concept  |
| `LandingPageProps`    | Auto-populated content (description, valueProposition, curriculumOutline, authorBio, etc.) |
| `TrackVisitPayload`   | UTM source attribution                                                                     |
| `SubscribePayload`    | `{email, utmSource?}`                                                                      |

## Constraints

- **`landing_page` tactic phải có trong mix** trước khi generate — xem [Tactics](./tactics.md).
- **Generate 1 lần** — re-generate cần `PATCH` (không POST lại).
- **Public visit dedup by IP** — multiple visits cùng IP chỉ count 1 reach (BE enforce). Test traffic light qua mock validation thay vì brute force public visit.
- **Email capture double opt-in** — `/subscribe` trả `status: "SUCCESS"` (new) hoặc `"ALREADY_REGISTERED"` (dup).
- **Concept dependency** — LP fail generate nếu campaign chưa có concept data (Phase A confirmed hoặc mock campaign).
- **UTM tracking** (Story 03.4.3) — `utmSource` lưu vào visit record cho analytics attribution.
- **Hero media** — `docs/hero-media-upload/` cho thumbnail; tách module riêng.

## Testing methods

| Method                | Apply                                                                         |
| --------------------- | ----------------------------------------------------------------------------- |
| Equivalence partition | UTM source: present/missing/null/long string · email: valid/invalid format    |
| Boundary              | Email length · burst visits count cho zone classification                     |
| State transition      | Subscribe: NEW → ALREADY_REGISTERED · LP: not-generated → generated → updated |
| Decision table        | Traffic light zone — xem [Dashboard Validation](./dashboard-validation.md)    |
| Security              | 401/403 creator endpoints · XSS trong email/UTM · SQLi                        |
| XSS                   | LP props (description, positioning) — stored XSS test surface                 |
| UX/UI                 | LP render trên public URL · responsive · empty/error state                    |

## Project references

- [`docs/landing-page-editor/`](../../../landing-page-editor/) — LP editor UI specs
- [`docs/utm-visit-tracking/`](../../../utm-visit-tracking/) — UTM tracking (Story 03.4.3)
- [`docs/squad coca/email-capture-with-double-opt-in/`](../../../squad%20coca/email-capture-with-double-opt-in/) — opt-in flow
- [`docs/hero-media-upload/`](../../../hero-media-upload/) — LP thumbnail upload
