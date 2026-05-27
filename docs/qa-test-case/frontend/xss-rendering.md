# Frontend — XSS Rendering

FE-layer XSS verification. BE storage/response escape ở [`backend/injection-xss.md`](../backend/injection-xss.md). FE = verify browser KHÔNG execute payload khi render.

## Categories

| Type              | Where                             | Test                                          |
| ----------------- | --------------------------------- | --------------------------------------------- |
| **Reflected XSS** | URL params / search highlight     | Render text literal, KHÔNG `<script>` parsed  |
| **Stored XSS**    | Backend data → FE render          | Same — escaped/sanitized text visible         |
| **DOM XSS**       | URL fragment (`#...`) → JS render | FE code dùng `textContent`, KHÔNG `innerHTML` |

## Expected FE behavior

| Layer                             | Expected                                                                |
| --------------------------------- | ----------------------------------------------------------------------- |
| Browser render                    | Literal `<script>alert(1)</script>` text visible — KHÔNG execute        |
| Framework auto-escape             | React/Vue/Angular auto-escape mặc định khi dùng `{value}` interpolation |
| `innerHTML` usage                 | ❌ NEVER với user input. Dùng `textContent`                             |
| `dangerouslySetInnerHTML` (React) | Chỉ allow sau khi sanitize qua DOMPurify hoặc whitelist                 |
| Markdown render                   | Sanitize step (vd `marked` + DOMPurify) trước render                    |

## Pattern: stored XSS render verification

```ts
test('[XSS] campaign title with <script> → rendered as text, NOT executed', async ({ page, request }) => {
    // 1. Setup: create campaign with XSS payload (BE escape or accept)
    const xssTitle = '<script>window.__xss=true</script>';
    await createMockCampaign(request, accessToken, { title: xssTitle });

    // 2. Render FE
    await page.goto(`/campaigns/${campaignId}`);

    // 3. Verify: title visible literally
    await expect(page.getByText('<script>window.__xss=true</script>')).toBeVisible();

    // 4. Verify: script did NOT execute
    const xssTriggered = await page.evaluate(() => (window as any).__xss);
    expect(xssTriggered).toBeUndefined();
});
```

## Pattern: reflected XSS in URL params

```ts
test('[XSS] search query echoed in heading → escaped', async ({ page }) => {
    await page.goto('/search?q=<img src=x onerror=window.__xss=true>');
    // Heading shows literal text
    await expect(page.locator('h1')).toContainText('<img src=x onerror=');
    // Script did not execute
    const triggered = await page.evaluate(() => (window as any).__xss);
    expect(triggered).toBeUndefined();
});
```

## Pattern: DOM XSS in URL fragment

```ts
test('[XSS] URL hash injection → not executed', async ({ page }) => {
    await page.goto('/profile#<script>window.__hash=true</script>');
    const triggered = await page.evaluate(() => (window as any).__hash);
    expect(triggered).toBeUndefined();
});
```

## 8 payload variants để test

| Type          | Payload                                                    |
| ------------- | ---------------------------------------------------------- |
| Script tag    | `<script>alert(1)</script>`                                |
| Event handler | `<img src=x onerror=alert(1)>`                             |
| JS pseudo-URL | `javascript:alert(1)` (trong href/src)                     |
| URL encoded   | `%3Cscript%3Ealert(1)%3C/script%3E`                        |
| HTML entity   | `&lt;script&gt;...&lt;/script&gt;`                         |
| SVG           | `<svg onload=alert(1)>`                                    |
| Unicode       | `<script>...</script>` (full-width)                        |
| Polyglot      | ``jaVasCript:/*-/*`/*\`/*'/*"/**/(/* */oNcliCk=alert() )`` |

## Project surfaces

Test stored XSS rendering ở các trường user-input render trên FE:

| Surface         | Field                                                              | File                                    |
| --------------- | ------------------------------------------------------------------ | --------------------------------------- |
| Campaign editor | title, description, valueProposition, curriculumOutline, authorBio | `docs/campaign-editor/`                 |
| Landing page    | LP props (auto-populated từ concept)                               | `docs/landing-page-editor/`             |
| Q&A             | question text, creator answer                                      | `docs/campaign-q-and-a/`                |
| Profile         | fullName, bio                                                      | `docs/manage-my-profile/`               |
| Email survey    | subject, body (markdown!)                                          | `docs/sprint_9/epic-03.7-email-survey/` |

## Checklist (FE XSS)

```
☐ Reflected XSS: URL param echo trong error message / search → escaped
☐ Stored XSS: title / description / comment / Q&A render → escaped
☐ DOM-based XSS: URL fragment (#...) render bằng JS → safe
☐ Tested 8 variants per surface
☐ Browser KHÔNG execute payload (verify via `window.__xss` flag)
☐ Text content literal visible (verify via `toContainText`)
☐ Markdown rendering sanitized (vd DOMPurify whitelist)
☐ `innerHTML` / `dangerouslySetInnerHTML` audit — KHÔNG raw user input
☐ Image `src` / link `href` / iframe `src` validated (no `javascript:` scheme)
```

## See also

- [backend/injection-xss.md](../backend/injection-xss.md) — BE escape/sanitize
- [anti-patterns.md](./anti-patterns.md)
- OWASP XSS Prevention Cheat Sheet
