# Frontend — Interactions (Form, Modal, Keyboard, Navigation)

UI interactive behavior test patterns.

## Form validation

| Layer                     | Test                                                                           |
| ------------------------- | ------------------------------------------------------------------------------ |
| **Field-level real-time** | Type invalid → error message bên dưới field tức thì (hoặc on blur theo design) |
| **Submit-level**          | Click Submit với fields empty → 1 hoặc nhiều error messages                    |
| **Server error**          | API trả 400 → form display server message (KHÔNG generic "Something wrong")    |
| **Success**               | API 200 → form reset OR redirect OR success state                              |

### Pattern: form validation

```ts
test('[form] empty submit → field errors visible', async ({ page }) => {
    await page.goto('/signup');
    await page.getByRole('button', { name: 'Sign up' }).click();
    await expect(page.getByText('Email is required')).toBeVisible();
    await expect(page.getByText('Password is required')).toBeVisible();
});

test('[form] invalid email format → field error', async ({ page }) => {
    await page.getByLabel('Email').fill('not-an-email');
    await page.getByLabel('Email').blur();
    await expect(page.getByText(/invalid email/i)).toBeVisible();
});
```

## Modal / Dialog

| Aspect            | Test                                                         |
| ----------------- | ------------------------------------------------------------ |
| **Open trigger**  | Click button → modal visible · backdrop visible              |
| **Focus trap**    | Tab xoay vòng trong modal · ESC return focus tới trigger     |
| **Scroll lock**   | Body scroll disabled khi modal open                          |
| **Close methods** | ESC key · backdrop click · close button (X) — cả 3 phải work |
| **Confirm flow**  | Confirm button → callback · Cancel → no callback             |

### Pattern: 3 close methods

```ts
test.describe('Modal close', () => {
    test('[modal] ESC → close', async ({ page }) => {
        await page.getByRole('button', { name: 'Open' }).click();
        await page.keyboard.press('Escape');
        await expect(page.locator('[role="dialog"]')).not.toBeVisible();
    });

    test('[modal] backdrop click → close', async ({ page }) => {
        await page.getByRole('button', { name: 'Open' }).click();
        await page.locator('[data-testid="modal-backdrop"]').click({ position: { x: 10, y: 10 } });
        await expect(page.locator('[role="dialog"]')).not.toBeVisible();
    });

    test('[modal] close button → close', async ({ page }) => {
        await page.getByRole('button', { name: 'Open' }).click();
        await page.getByRole('button', { name: /close/i }).click();
        await expect(page.locator('[role="dialog"]')).not.toBeVisible();
    });
});
```

## Keyboard navigation

⚠️ **KHÔNG tự suy WCAG** — chỉ test nếu design spec đòi.

| Key          | Common behavior                          |
| ------------ | ---------------------------------------- |
| `Tab`        | Move focus forward — tab order logical   |
| `Shift+Tab`  | Move focus backward                      |
| `Enter`      | Submit form / activate button            |
| `ESC`        | Close modal/popover / cancel inline edit |
| `Space`      | Toggle checkbox/button                   |
| `Arrow keys` | Navigate within list/menu                |

### Pattern: tab order

```ts
test('[keyboard] tab order theo design spec', async ({ page }) => {
    await page.goto('/signup');
    await page.keyboard.press('Tab');
    await expect(page.getByLabel('Email')).toBeFocused();
    await page.keyboard.press('Tab');
    await expect(page.getByLabel('Password')).toBeFocused();
    await page.keyboard.press('Tab');
    await expect(page.getByRole('button', { name: 'Sign up' })).toBeFocused();
});
```

## Navigation

| Aspect           | Test                                                               |
| ---------------- | ------------------------------------------------------------------ |
| **Back button**  | Browser back preserve state · không lose form data nếu design spec |
| **Deep link**    | Direct URL → render đúng page · auth redirect nếu cần              |
| **404 page**     | Invalid path → 404 page render · CTA về home                       |
| **Route guards** | Logged-out user truy cập `/dashboard` → redirect `/login`          |

### Pattern: route guard

```ts
test('[nav] logged-out access /dashboard → redirect /login', async ({ playwright }) => {
    const ctx = await playwright.request.newContext(); // no cookies
    // E2E equivalent: use fresh context with no storage state
    const page = (await ctx.newPage?.()) || (await playwright.chromium.launch()).newContext().newPage();
    await page.goto('/dashboard');
    await expect(page).toHaveURL(/\/login/);
});
```

## i18n

| Aspect                   | Test                                               |
| ------------------------ | -------------------------------------------------- |
| **Text fits**            | English + Vietnamese text không overflow container |
| **Date format**          | DD/MM/YYYY vs MM/DD/YYYY theo locale               |
| **Number format**        | Decimal comma vs period                            |
| **RTL** (nếu app hỗ trợ) | Layout mirror cho Arabic/Hebrew                    |

## Project tools

| Tool                                                            | Mục đích                                 |
| --------------------------------------------------------------- | ---------------------------------------- |
| `src/selectors/*.selectors.ts`                                  | Centralized locators — locator-first POM |
| `src/fixtures/e2e-*.fixture.ts`                                 | E2E setup (auth + nav + data seed)       |
| MCP `browser_click` / `browser_fill_form` / `browser_press_key` | Debug interactions                       |
| MCP `browser_snapshot`                                          | DOM state inspection                     |

## Checklist

```
☐ Form: empty submit · partial fill · invalid format · server error · success
☐ Field-level real-time validation theo design spec
☐ Modal: open via trigger · close via 3 methods (ESC, backdrop, close btn)
☐ Modal: focus trap · scroll lock
☐ Keyboard nav theo design spec (KHÔNG tự suy WCAG)
☐ Tab order logical
☐ Back button preserve state nếu design spec
☐ Deep link works · auth redirect đúng
☐ 404 page render
☐ i18n: VN/EN fits container · date/number format
```

## See also

- [visual-states.md](./visual-states.md)
- [anti-patterns.md](./anti-patterns.md)
- Project: `src/selectors/concept-validation.selectors.ts` · `src/fixtures/e2e.fixture.ts`
