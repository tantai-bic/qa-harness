# Backend — Injection & XSS (BE layer)

Backend testing cho input validation guards. Phần XSS này tập trung **BE storage layer + response escape** — XSS DOM rendering ở [`frontend/xss-rendering.md`](../frontend/xss-rendering.md).

## Categories

| Category                               | Apply                                                                 |
| -------------------------------------- | --------------------------------------------------------------------- |
| **SQL Injection**                      | Input `' OR 1=1--` → 400/401, không 500 / dump                        |
| **XSS (stored)**                       | Input `<script>` → BE 400 reject hoặc escape khi store                |
| **XSS (reflected)**                    | Input echo trong error message / search highlight → escaped           |
| **Path traversal**                     | `../../etc/passwd` trong file param → 400                             |
| **Command injection**                  | `;rm -rf /` trong shell-piped fields → 400                            |
| **NoSQL injection**                    | `{"$gt":""}` trong fields gọi DB → reject                             |
| **LDAP injection**                     | `*` wildcard trong auth fields                                        |
| **XXE (XML external entity)**          | Áp dụng nếu BE parse XML uploads                                      |
| **Server-Side Request Forgery (SSRF)** | URL field input `http://localhost:6379/` → reject hoặc whitelist      |
| **Prototype pollution**                | `{"__proto__":{"isAdmin":true}}` → BE Object.create(null) hoặc reject |

## XSS payload variants

| Type          | Payload                                                    | Inject vào                              |
| ------------- | ---------------------------------------------------------- | --------------------------------------- |
| Script tag    | `<script>alert(1)</script>`                                | Title, name, description, comment       |
| Event handler | `<img src=x onerror=alert(1)>`                             | Image src, avatar URL                   |
| JS pseudo-URL | `javascript:alert(1)`                                      | Link href, redirect URL                 |
| URL encoded   | `%3Cscript%3Ealert(1)%3C/script%3E`                        | URL params                              |
| HTML entity   | `&lt;script&gt;alert(1)&lt;/script&gt;`                    | Verify entity NOT decoded then executed |
| SVG           | `<svg onload=alert(1)>`                                    | File upload, rich text                  |
| Unicode       | `<script>...</script>`                                     | JSON body                               |
| Polyglot      | ``jaVasCript:/*-/*`/*\`/*'/*"/**/(/* */oNcliCk=alert() )`` | Universal bypass test                   |

## Expected behavior (BE layer)

| Layer               | Expected                                                                             |
| ------------------- | ------------------------------------------------------------------------------------ |
| BE input validation | **400 reject** (preferred) OR strip dangerous content OR escape entity               |
| BE storage          | If accepted, stored as **escaped/sanitized** (not raw `<script>`)                    |
| BE response         | Echo as escaped HTML entities trong JSON string                                      |
| Status semantics    | 400 = format reject · 422 = semantic reject · 200 + sanitized = accepted-but-cleaned |

## Project examples

- `POST /mock/campaigns {title: '<script>...'}` → 400 (BE XSS guard) — xem [`phaseA.md`](../../../../docs/roadmap/campaign/phaseA.md)
- Refinement responses (Q1-Q7) — `submitResponseForSecurityTest` helper
- Login fields — `loginForSecurityTest` helper
- Email survey content (markdown) — stored XSS risk

## Pattern: SQL injection (login)

```ts
test('[Security] SQLi in email → blocked', async ({ request }) => {
    const res = await loginForSecurityTest(request, {
        email: "admin' OR '1'='1",
        password: 'anything',
    });
    // 400 (format) or 401 (no match) — both = BLOCKED
    expect([400, 401]).toContain(res.status());
});
```

## Pattern: Stored XSS verification

```ts
// 1. Submit XSS payload
const xss = '<script>alert(1)</script>';
await createMockCampaign(request, accessToken, { title: xss });

// 2. Read back — should be escaped or rejected
const { campaign } = await getCampaign(request, campaignId, accessToken);
expect(campaign.title).not.toContain('<script>'); // escaped or stripped
// OR
expect(response.status()).toBe(400); // BE rejected upfront
```

## Checklist

```
☐ SQLi: input `' OR 1=1--` → 400/401, không 500 / dump
☐ XSS stored: data lưu DB → escaped khi read back
☐ XSS reflected: error message / search highlight → escaped
☐ Path traversal: `../../etc/passwd` → 400
☐ Command injection: `;rm -rf /` trong shell-piped fields → 400
☐ NoSQL: `{"$gt":""}` → reject
☐ SSRF: localhost / internal IPs trong URL fields → reject
☐ Tested 8 XSS variants per input field
☐ BE response Content-Type `application/json` ⇒ JSON-string-escape verified
☐ Error response không leak stack trace
☐ Status code đúng (400 reject vs 200 sanitized vs 422 semantic)
```

## See also

- [security.md](./security.md) — auth/authz/rate limit
- [frontend/xss-rendering.md](../frontend/xss-rendering.md) — FE escape verification
- [`/_bmad-output/project-context.md`](../../../../_bmad-output/project-context.md) — Security Testing Pattern
