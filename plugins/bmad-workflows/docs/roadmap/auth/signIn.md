# Auth — Sign In (Login)

Đổi credentials lấy session token. `POST /auth/login` trả `accessToken` + `refreshToken` (body khi `AUTH_RESPONSE_TOKEN_ENABLED=true`) hoặc Set-Cookie (`_at`/`_rt`/`_uid`). Đây là **gateway** cho mọi authenticated API trong project — KHÔNG có login = KHÔNG có gì hoạt động downstream.

## State

| Field                                         | Value sau login thành công                                                                |
| --------------------------------------------- | ----------------------------------------------------------------------------------------- |
| HTTP                                          | `200 OK`                                                                                  |
| Body (env `AUTH_RESPONSE_TOKEN_ENABLED=true`) | `{accessToken, refreshToken, accessTokenExpiresAt, refreshTokenExpiresAt}`                |
| Body (env false — default)                    | EMPTY, tokens chỉ trong Set-Cookie                                                        |
| Cookies                                       | `_at` (HttpOnly, Secure, SameSite=Lax, Path=/), `_rt` (Path=/auth), `_uid` (NOT HttpOnly) |
| Access token TTL                              | **30 phút** (BE thực tế, KHÔNG phải 168h như test design — F-7)                           |
| Refresh token TTL                             | Lâu hơn (sliding window theo BE config)                                                   |

## Upstream (deps để gọi login)

| Cần                                    | Nguồn                                                                                                                                          |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| BE auth service up                     | `BASE_API_URL` env config                                                                                                                      |
| Account đã tồn tại                     | Hoặc (a) signup mới qua [`signUp.md`](./signUp.md), hoặc (b) `TEST_USER_EMAIL`/`TEST_USER_PASSWORD` từ `.env` (10 shared users TEST_USER1..10) |
| Account chưa locked                    | Sau 5 lần `loginWithInvalidCredentials` → BE lock account 30 phút                                                                              |
| Email verified _(nếu feature yêu cầu)_ | Một số endpoint reject nếu `emailVerified=false`                                                                                               |

## Downstream (Sign In unlocks — TẤT CẢ authenticated API)

| Domain                 | Unlock                                                                   |
| ---------------------- | ------------------------------------------------------------------------ |
| **Campaign lifecycle** | [`campaign/phaseA.md`](../campaign/phaseA.md) → phaseB → phaseC → phaseD |
| **Refinement**         | `POST /refinements/start` + Q1-Q7                                        |
| **Validation**         | `POST /campaigns/:id/validations`                                        |
| **Pledge / Checkout**  | `POST /campaigns/:id/pledges`                                            |
| **Delivery**           | `POST /deliveries`                                                       |
| **Dashboard**          | `GET /dashboard/*` (creator dashboard, activity feed)                    |
| **Device management**  | `GET/DELETE /auth/devices`                                               |
| **Refresh**            | `POST /auth/refresh` (cần refresh token hợp lệ)                          |
| **Logout**             | `POST /auth/logout` (cần refresh token)                                  |

## Real flow (~0.5-1s)

| #   | Endpoint                                            | Note                                    |
| --- | --------------------------------------------------- | --------------------------------------- |
| 1   | `POST /auth/login {email, password}`                | 200 + body hoặc Set-Cookie              |
| 2   | Extract `accessToken` từ body **hoặc** cookies      | Phụ thuộc `AUTH_RESPONSE_TOKEN_ENABLED` |
| 3   | (optional) `GET /auth/lockout-status` với Bearer    | Verify session active                   |
| 4   | Use `Bearer ${accessToken}` cho mọi downstream call |                                         |

## Auth state cho CI / cross-test reuse (~0.5s/session)

`src/auth/global-setup.ts` chạy 1 lần trước suite — login via API + save storage state vào `.auth/user.json`. Subsequent tests dùng `storageState` config (Playwright reuses cookies). Token expiry check: nếu stale → re-login.

```
npm run auth          ← run setup
npm run auth:delete   ← invalidate
npm run auth:status   ← check expiry
```

## Service / Factory / Helper layer

| Layer             | File · Symbol                                                                                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Service login     | `src/auth/login/login.service.ts` → `loginWithValidCredentials` · `loginWithPayload` · `loginWithInvalidCredentials` · `loginForSecurityTest` · `loginForEdgeCaseTest` |
| Service logout    | same file → `logout` · `logoutWithoutToken` · `logoutWithInvalidToken` · `verifyTokenInvalid`                                                                          |
| Service refresh   | same file → `refreshToken` · `refreshTokenWithoutCookie`                                                                                                               |
| Service lockout   | same file → `attemptLoginMultipleTimes` · `getLockoutStatus`                                                                                                           |
| Service devices   | same file → `getActiveDevices` · `removeDevice`                                                                                                                        |
| Verifiers         | same file → `verifyLoginResponseStructure` · `verifyCookieHeaders` · `verifySessionExpiry` · `calculateExpectedExpiry`                                                 |
| Test setup helper | same file → `createTestUser` (signup + return creds, KHÔNG auto-login)                                                                                                 |
| Factory           | `src/auth/login/login.factory.ts`                                                                                                                                      |
| Global setup      | `src/auth/global-setup.ts` → `authenticateViaAPI` (storage state CI)                                                                                                   |
| E2E fixture       | `src/fixtures/login.fixture.ts` → reads `TEST_USER_EMAIL`/`TEST_USER_EMAIL_BLOCK` từ `.env`                                                                            |

## Types (`src/auth/auth.types.ts`)

| Type                                                                                     | Note                                                   |
| ---------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| `LoginPayload {email, password}`                                                         | Request body                                           |
| `LoginResponse {accessToken, refreshToken, accessTokenExpiresAt, refreshTokenExpiresAt}` | **Chỉ có body khi `AUTH_RESPONSE_TOKEN_ENABLED=true`** |
| `AuthUser {id, email, roles, emailVerified}`                                             | User profile sau login                                 |
| `LockoutStatusResponse {isLocked, remainingTime?}`                                       | GET /auth/lockout-status                               |
| `RefreshTokenResponse`                                                                   | Same shape as LoginResponse                            |
| `ErrorResponse`                                                                          | 4xx body                                               |

## Mocks available

| Mock        | Endpoint | Effect                                                                   |
| ----------- | -------- | ------------------------------------------------------------------------ |
| ❌ Không có | —        | Login luôn hit real BE. Shortcut = `global-setup.ts` cache storage state |

## Constraints (failure log)

- **F-1** — KHÔNG `request.post('/auth/login', ...)` trực tiếp. Đi qua `LoginService.loginWithValidCredentials` (TestLogger + verify pattern).
- **F-7 (access token TTL)** — BE thực tế **30 phút**, KHÔNG phải 168h như test design spec. `verifySessionExpiry` đã align với behavior thực; đừng "fix" theo spec.
- **Invalid credentials → 401** (không 400). 5 lần liên tiếp → **403 Locked** (30 phút).
- **Logout requires refresh token** trong body (mobile) hoặc cookie (web). Empty → 400. Invalid → 401. Success → 204 (no content).
- **Refresh requires refresh token**. Empty body + no cookie → 400.
- Token sau logout phải invalid (`verifyTokenInvalid` returns true). Re-use → 401.
- Cookie security flags BẮT BUỘC: `HttpOnly` cho `_at`/`_rt`; `Secure` + `SameSite=Lax` cho cả 3; `_uid` KHÔNG HttpOnly (FE đọc để display).
- **Fixture cookies leak** (F-1 bonus) — Playwright default `request` fixture giữ cookies giữa calls. Test 401/403 phải `playwright.request.newContext()` cho `*WithoutAuth()` để tránh accidentally-authenticated 200.
- Token expiry tolerance 2 phút (account cho test execution time) — `verifySessionExpiry`.

## Khi nào dùng login fresh vs reuse?

| Use-case                                                          | Dùng                                                                   | Cost                             |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------- | -------------------------------- |
| Smoke / regression suite                                          | Global setup + storage state                                           | ~0.5s reuse                      |
| Test isolated (cần fresh creator, không có prior dashboard state) | signup + login mỗi test                                                | ~2s                              |
| Test parallel (data drift risk)                                   | signup + login mỗi test                                                | Mandatory                        |
| Test rate limit / lockout                                         | `attemptLoginMultipleTimes` với wrong password                         | 5 calls                          |
| Test session expiry                                               | login + chờ 30 phút **hoặc** mock token                                | Slow — chỉ trong nightly         |
| Test logout / token invalidation                                  | login → logout → `verifyTokenInvalid`                                  | ~1.5s                            |
| Test refresh token rotation                                       | login → refresh → verify new token                                     | ~1s                              |
| Test 401 (unauthenticated)                                        | `playwright.request.newContext()` riêng — KHÔNG dùng fixture default   | F-1 bonus                        |
| Negative login                                                    | `loginWithInvalidCredentials` / `loginWithPayload({password:'wrong'})` | Expect 401                       |
| Security test (SQLi/XSS)                                          | `loginForSecurityTest`                                                 | Accept 400/401/403 all = BLOCKED |
| Social login                                                      | `POST /auth/social/login` (separate service TBD)                       | —                                |
| Guest login                                                       | `POST /auth/guest/login` — `src/auth/guest-user/guest-user.service.ts` | —                                |

## Endpoints reference (`src/constants/api.constants.ts`)

```
AUTH.LOGIN              POST /auth/login                ← obtain tokens
AUTH.LOGOUT             POST /auth/logout               ← invalidate refresh token (204)
AUTH.REFRESH_TOKEN      POST /auth/refresh              ← rotate access token
AUTH.LOCKOUT_STATUS     GET  /auth/lockout-status       ← session/lock check (Bearer)
AUTH.DEVICES            GET/DELETE /auth/devices[/:id]  ← active session management
AUTH.SOCIAL_LOGIN       POST /auth/social/login         ← OAuth callback
GUEST_AUTH.LOGIN        POST /auth/guest/login          ← guest token (limited scope)
ADMIN_AUTH.LOGIN        POST /admin/auth/login          ← admin role (separate flow)
```

## Related

- [`signUp.md`](./signUp.md) — upstream (account creation).
- [`docs/api/auth-api-contract.md`](../../api/) — full BE contract.
- [`docs/sign-in-with-social/`](../../sign-in-with-social/) — social login variant.
- [`docs/password-reset/`](../../password-reset/) — password recovery flow.
- [`src/fixtures/login.fixture.ts`](../../../src/fixtures/login.fixture.ts) — E2E fixture (env-based credentials).
- `.env` keys: `TEST_USER_EMAIL/PASSWORD`, `TEST_USER1..10_EMAIL` (parallel), `TEST_USER_EMAIL_BLOCK` (pre-locked).
