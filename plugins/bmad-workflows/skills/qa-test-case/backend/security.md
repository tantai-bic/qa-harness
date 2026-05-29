# Backend — Security Testing

Categories cho API/BE security tests.

## Categories

| Category                    | Apply                                                                                       |
| --------------------------- | ------------------------------------------------------------------------------------------- |
| **AuthN** (401)             | Endpoint require Bearer? → call WITHOUT token → expect 401                                  |
| **AuthZ** (403)             | User A truy cập tài nguyên user B → expect 403                                              |
| **Rate limit** (429)        | N rapid calls → expect 429 hoặc account lock                                                |
| **Token lifecycle**         | Logout → re-use access token → expect 401                                                   |
| **Session fixation**        | Refresh token → old token invalidated → expect 401 on old                                   |
| **CSRF**                    | Cookie-based — verify `SameSite=Lax`, no GET state-changing endpoint                        |
| **Mass assignment**         | POST/PATCH với extra fields (`isAdmin:true`) → BE strip hoặc reject                         |
| **IDOR**                    | Numeric/UUID swap — user A guess user B's resource ID → 403                                 |
| **Sensitive data exposure** | Response không leak password hash, internal IDs, stack trace                                |
| **JWT tampering**           | Alter payload → 401 (signature invalid)                                                     |
| **Cookie security flags**   | `_at`/`_rt`: HttpOnly + Secure + SameSite=Lax; `_uid`: Secure + SameSite=Lax (NOT HttpOnly) |

## Pattern: 401 (no auth) — fresh context

⚠️ **Critical** — F-1 bonus: Playwright fixture default `request` giữ cookies giữa calls. Test 401/403 phải dùng fresh `request.newContext()`, không thì test "401 unauth" actually returns 200 vì cookies từ prior test leak vào.

```ts
test('[Security] Unauth GET → 401', async ({ playwright }) => {
    const ctx = await playwright.request.newContext(); // fresh, no cookies
    const res = await ctx.get(`${BASE}/campaigns`);
    expect(res.status()).toBe(401);
});
```

## Pattern: 403 (cross-user IDOR)

```ts
test('[Security] User A cannot read user B campaign', async ({ request }) => {
    const userA = await signupFreshCreator(request);
    const userB = await signupFreshCreator(request);
    const { campaign } = await createMockCampaign(request, userB.accessToken);

    // User A tries to fetch user B's campaign
    const res = await getCampaign(request, campaign.id, userA.accessToken);
    expect(res.status()).toBe(403);
});
```

## Pattern: Rate limit

```ts
test('[Security] 5x failed login → account locked', async ({ request }) => {
    const res = await attemptLoginMultipleTimes(request, email, 'wrong', 5);
    expect(res.status()).toBe(403); // last attempt = Locked
});
```

## Service helpers project

| Helper                               | Mục đích                                                   |
| ------------------------------------ | ---------------------------------------------------------- |
| `loginForSecurityTest`               | SQLi/XSS payloads cho login — accept 400/401/403 = BLOCKED |
| `submitResponseForSecurityTest`      | Malicious refinement payload — accept 4xx                  |
| `*WithoutAuth` (all services)        | Fresh context, no Bearer header → expect 401               |
| `*WithInvalidToken` (auth services)  | Bad token → 401                                            |
| `withFreshContext<T>` (email-survey) | Wrap callback với fresh request context (no cookies)       |

## Checklist

```
☐ 401 unauth: fresh request.newContext (no cookies — F-1 bonus)
☐ 403 unauthorized resource: user A truy cập tài nguyên user B (IDOR)
☐ 429 rate limit: brute force / spam payload
☐ Token lifecycle: logout → reuse → 401
☐ Refresh token rotation: old token invalidated
☐ CSRF: SameSite=Lax cookie verified · no GET state-changing
☐ Mass assignment: extra fields stripped (vd `isAdmin:true` ignored)
☐ JWT tampering: alter payload → 401
☐ Sensitive data: no password hash, no internal stack trace in response
☐ Cookie flags: HttpOnly, Secure, SameSite=Lax verified
☐ Logout invalidates token (verify GET sau logout → 401)
```

## See also

- [injection-xss.md](./injection-xss.md) — input validation security
- [`docs/roadmap/auth/signIn.md`](../../../../docs/roadmap/auth/signIn.md) — lockout, refresh, devices
- [`/_bmad-output/project-context.md`](../../../../_bmad-output/project-context.md) — Security Testing Pattern
