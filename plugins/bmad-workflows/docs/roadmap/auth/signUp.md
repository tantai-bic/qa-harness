# Auth — Sign Up

Tạo account mới với email + password + fullName. Endpoint `POST /auth/signup` trả 201 **không body** — token phải lấy qua `/auth/login` riêng (xem [signIn.md](./signIn.md)).

## State

| Field            | Value sau signup thành công                                     |
| ---------------- | --------------------------------------------------------------- |
| HTTP             | `201 Created`                                                   |
| Body             | ⚠️ **EMPTY** (per API contract `docs/api/auth-api-contract.md`) |
| Account state BE | tạo user record, `emailVerified=false`                          |
| Session          | ❌ chưa có (cần login riêng)                                    |

⚠️ Một số env BE cũ có thể trả body với `accessToken` — KHÔNG rely. Type `SignupResponse` mark optional cho backward-compat.

## Upstream (deps để gọi signup)

| Cần                | Nguồn                                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------------------- |
| BE auth service up | `BASE_API_URL` ở env config                                                                             |
| Email chưa tồn tại | Factory generate unique `test_{timestamp}_{random}@example.com` để parallel-safe                        |
| Password đúng rule | `generateValidPassword()`: 8-15 char, ≥1 upper + ≥1 lower + ≥1 number + ≥1 special                      |
| Full name sạch     | `generateFullName()`: firstName + lastName, strip non-letter/space (faker có thể chèn `Dr.` `Jr.` etc.) |

## Downstream (Sign Up unlocks)

| Bước tiếp                     | Endpoint                                          | Mục đích                                                                                |
| ----------------------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------- |
| **Login**                     | `POST /auth/login`                                | Lấy `accessToken`/`refreshToken` (hoặc cookies) — TẤT CẢ authenticated API phải qua đây |
| **Verify email** _(optional)_ | `POST /auth/verify-email`                         | Một số features đòi `emailVerified=true`                                                |
| **Phase A Concept**           | xem [`campaign/phaseA.md`](../campaign/phaseA.md) | Sau login, có `accessToken` → tạo mock/real campaign                                    |

## Real flow (~1s)

| #   | Endpoint                                                         | Note                           |
| --- | ---------------------------------------------------------------- | ------------------------------ |
| 1   | `POST /auth/signup {email, password, fullName}`                  | 201, NO body                   |
| 2   | `POST /auth/login {email, password}`                             | Lấy tokens (xem signIn.md)     |
| 3   | (optional) Verify session: `GET /auth/lockout-status` với Bearer | 200 → user tồn tại + chưa lock |

## Helper shortcut (test setup)

| Helper               | File · Symbol                                                           | Trả về                                                                |
| -------------------- | ----------------------------------------------------------------------- | --------------------------------------------------------------------- |
| `createTestUser`     | `src/auth/login/login.service.ts` → `createTestUser(request, testName)` | `{email, password}` (chưa login)                                      |
| `signupFreshCreator` | `src/auth/signup/signup.service.ts` (signup) hoặc fixture chain         | Helper combo: signup + login + accessToken (kết hợp với LoginService) |

Pattern recommended: signup → login → reuse accessToken cho phần còn lại test.

## Service / Factory / Helper layer

| Layer                  | File · Symbol                                                                                                                                  |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Service signup         | `src/auth/signup/signup.service.ts` → `signupWithValidData` · `signupWithPayload` · `signupWithDuplicateEmail`                                 |
| Factory                | `src/auth/signup/signup.factory.ts` → `createSignupPayload(overrides?)` · `generateUniqueEmail` · `generateValidPassword` · `generateFullName` |
| Email verification     | `POST /auth/verify-email` (helper chưa wrap — gọi qua service tương lai)                                                                       |
| Global setup (CI auth) | `src/auth/global-setup.ts` → `authenticateViaAPI` (storage state cho TEST_USER)                                                                |

## Types (`src/auth/auth.types.ts`)

| Type                                                   | Note                                                                                     |
| ------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| `SignupPayload {email, password, fullName}`            | Required 3 fields                                                                        |
| `SignupResponse`                                       | All fields **optional** (per contract: empty body). Còn lại optional cho backward-compat |
| `ErrorResponse {success:false, error:{code, message}}` | Error shape khi 4xx/5xx                                                                  |

## Mocks available

| Mock        | Endpoint | Effect                                                               |
| ----------- | -------- | -------------------------------------------------------------------- |
| ❌ Không có | —        | Signup luôn hit real BE. Test parallel-safe nhờ unique email factory |

## Constraints (failure log)

- **F-2** — KHÔNG hardcode email `test@example.com`. Dùng `generateUniqueEmail()` (timestamp + random) — tránh đụng độ parallel test data BE.
- **F-1** — KHÔNG `request.post('/auth/signup', ...)` trực tiếp. Đi qua `SignupService.signupWithValidData` (TestLogger + verify pattern).
- Password rules (BE enforce 400):
    - Length 8-15 chars (>15 → 400)
    - ≥1 uppercase, ≥1 lowercase, ≥1 number, ≥1 special (`!@#$%&*` etc.)
- Email format BE validate strictly — `invalid@` / `@example.com` / `not-an-email` → 400.
- Full name BE accept letters + spaces; reject `<script>` / số / một số dấu nháy.
- Duplicate email → **409 Conflict** (không phải 400).
- 201 body **EMPTY** theo contract — đừng assert `body.accessToken` ngay sau signup. Phải call login.
- Rate limit ở signup: chưa observed; nhưng tạo >100 user/min có thể trigger BE rate limiter.

## Khi nào dùng signup mới vs reuse?

| Use-case                                                          | Dùng                                      | Note                    |
| ----------------------------------------------------------------- | ----------------------------------------- | ----------------------- |
| Test isolated (cần fresh state, không đụng dữ liệu test khác)     | `signupWithValidData` + login             | ~2s combined            |
| Test parallel safe (Phase B mock single-shot, fixture data drift) | `signupWithValidData` + login             | Mandatory fresh account |
| Smoke test / regression dùng dashboard                            | `TEST_USER_EMAIL` từ `.env` + login       | ~1s — không cần signup  |
| Test rate limit / lockout (cần "blocked" account)                 | `TEST_USER_EMAIL_BLOCK` từ `.env`         | Pre-locked account      |
| Test negative (duplicate email)                                   | `signupWithDuplicateEmail(existingEmail)` | Expect 409              |
| Test negative (password rule violation)                           | `signupWithPayload({password:'weak'})`    | Expect 400              |
| Negative test email format                                        | `signupWithPayload({email:'invalid'})`    | Expect 400              |

## Endpoints reference (`src/constants/api.constants.ts`)

```
AUTH.SIGNUP          POST /auth/signup               ← create account
AUTH.LOGIN           POST /auth/login                ← obtain tokens (next step)
AUTH.VERIFY_EMAIL    POST /auth/verify-email
AUTH.LOCKOUT_STATUS  GET  /auth/lockout-status       ← verify account exists / lock state
```

## Related

- [`signIn.md`](./signIn.md) — next required step sau signup.
- [`docs/api/auth-api-contract.md`](../../api/) — full BE contract.
- [`docs/sign-in-with-social/`](../../sign-in-with-social/) — social signup variant.
- [`docs/password-reset/`](../../password-reset/) — password recovery flow.
