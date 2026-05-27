# Phase B → Module: Email Survey

Tactic type `email_survey`: creator gửi email survey tới list recipients (≤ vài trăm), audience click `Register Interest` link → email captured + tracked. Result = `recipientCount` (sent) + `interestedCount` (registered) → traffic light zone input.

## Scope

| Field          | Value                                                                                           |
| -------------- | ----------------------------------------------------------------------------------------------- |
| API base       | `/campaigns/:cId/validations/:vId/tactics/:tId/email-survey/*`                                  |
| Required state | `status=draft` cho content + email-list setup · `status=running` cho register-interest tracking |
| Output         | `recipientCount`, `interestedCount`, `analytics{opens, clicks, registrations}`                  |

## Upstream

| Cần                                                              | Nguồn                                                                                 |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `accessToken`                                                    | [`../../auth/signIn.md`](../../auth/signIn.md)                                        |
| `campaignId` + `validationId` + `tacticId` (type=`email_survey`) | [Tactics](./tactics.md)                                                               |
| Email content                                                    | BE generate từ concept (auto-template) hoặc creator override qua `updateEmailContent` |
| Recipient list ≥1 email                                          | Bắt buộc trước `startValidation` (BE 400 nếu empty)                                   |

## Downstream

| Bước tiếp                                         | Mục đích                                                   |
| ------------------------------------------------- | ---------------------------------------------------------- |
| [Duration](./duration.md) + start                 | Cần recipients ≥1 — BE enforce                             |
| BE auto-send emails                               | Sau `startValidation`, BE gửi survey emails tới recipients |
| Public register-interest                          | Audience click email link → `POST .../register-interest`   |
| [Dashboard Validation](./dashboard-validation.md) | Analytics: `opens`/`clicks`/`registrations` ratio          |

## Endpoints

```
# Content (auth, draft)
POST   .../email-survey/content                  ← save email content
GET    .../email-survey/content                  ← read

# Recipient list (auth, draft)
POST   .../email-survey/email-list               ← save list of emails
GET    .../email-survey/email-list               ← read

# Test send (auth)
POST   .../email-survey/send-test                ← send test email tới creator

# Analytics (auth, runtime)
GET    .../email-survey/recipients               ← paginated recipients + status
GET    .../email-survey/analytics                ← aggregate metrics
GET    .../email-survey/export-recipients        ← CSV export

# Public (no auth) — Story 03.7.x
POST   /public/email-survey/register-interest    ← audience opt-in
```

| Endpoint                              | Method                         | Gate |
| ------------------------------------- | ------------------------------ | ---- |
| `content` POST · `email-list` POST    | 🔒 setup                       |
| `send-test` POST                      | ⚡ any state (creator preview) |
| `recipients`/`analytics`/`export` GET | 📖 read                        |
| Public `register-interest`            | ⚡ runtime (after start)       |

## Service layer (`src/validation/email-survey/email-survey.service.ts`)

| Function                                                                    | Mục đích                                                              |
| --------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `getEmailContent` · `updateEmailContent`                                    | Content CRUD                                                          |
| `sendTestEmail(request, accessToken, cId, vId, tId, testName)`              | Preview test email                                                    |
| `saveEmailList(request, accessToken, cId, vId, tId, {emails}, testName)`    | Save recipient list                                                   |
| `getEmailList`                                                              | Read                                                                  |
| `getRecipients(request, accessToken, cId, vId, tId, queryParams, testName)` | Paginated recipients + delivery status                                |
| `exportRecipientsCsv`                                                       | CSV                                                                   |
| `getAnalytics`                                                              | Aggregate (opens/clicks/registrations)                                |
| `registerInterest(request, payload, testName)`                              | Public audience opt-in (uses fresh `request.newContext()` internally) |
| `withFreshContext<T>(...)`                                                  | Helper wrap callback với fresh request context (cookies-free)         |
| `*NoAuth` variants                                                          | 401 tests                                                             |
| `email-open-tracker.ts`                                                     | Pixel tracking helper                                                 |

### Factory (`email-survey.factory.ts`)

Generates valid email lists, content payloads, register-interest payloads.

## Types (`src/validation/email-survey/email-survey.types.ts`)

| Type                      | Note                                                                               |
| ------------------------- | ---------------------------------------------------------------------------------- | -------- | --------- | ------------ | --------- | ----------------------- |
| `EmailContent`            | Subject + body (markdown) + CTA                                                    |
| `EmailListPayload`        | `{emails: string[]}`                                                               |
| `Recipient`               | `{email, status: 'sent'                                                            | 'opened' | 'clicked' | 'registered' | 'bounced' | 'failed', sentAt, ...}` |
| `Analytics`               | `{totalSent, opens, clicks, registrations, openRate, clickRate, registrationRate}` |
| `RegisterInterestPayload` | `{email, validationId, tacticId, utmSource?}`                                      |

## Constraints

- **Min 1 recipient** trước `startValidation` — empty list → 400.
- **Max recipients per validation** — BE limit (xem story spec; thường ≤500 cho free tier).
- **Email format strict** — invalid format trong list → 400 với specific row index.
- **Duplicate dedup** — BE dedup recipients trong cùng list.
- **Test send creator-only** — `send-test` gửi về creator email, không count vào analytics.
- **Public register-interest dedup by email** — re-submit cùng email → `ALREADY_REGISTERED` status.
- **Email content markdown** — BE render markdown → HTML; XSS guard escape script tags.
- **Content language** — BE generate VN/EN dựa trên creator locale.

## Testing methods

| Method                | Apply                                                                                                     |
| --------------------- | --------------------------------------------------------------------------------------------------------- |
| Boundary              | Recipients count: 0, 1, 2, MAX-1, MAX, MAX+1 · email length                                               |
| Equivalence partition | Valid email vs invalid format vs special chars vs unicode domain                                          |
| State transition      | Recipient lifecycle: sent → opened → clicked → registered (or bounced/failed)                             |
| Decision table        | register-interest gating: validation status × email registered Y/N                                        |
| Security              | XSS trong subject/body markdown · CSRF cho register-interest public endpoint · spam protection rate limit |
| XSS                   | Content body (rich text) — stored XSS · email rendering                                                   |
| UX/UI                 | Email preview · recipient table pagination · analytics chart empty state                                  |

## Project references

- [`docs/sprint_9/epic-03.7-email-survey/`](../../../sprint_9/epic-03.7-email-survey/) — full epic (story-03.7.2 default content template, BDD, analytics, e2e exploration)
- [`docs/sprint_9/epic-03.7-email-survey/api-contract.md`](../../../sprint_9/epic-03.7-email-survey/) — BE contract
