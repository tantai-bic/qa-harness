# Frontend — Anti-patterns

FE-specific anti-patterns. KHÔNG vi phạm — hooks layer-1 enforce một số rule.

## 5 critical anti-patterns

| #   | Anti-pattern                                                           | Why bad                                               | Fix                                                                   |
| --- | ---------------------------------------------------------------------- | ----------------------------------------------------- | --------------------------------------------------------------------- |
| 1   | `expect(button).toBeVisible()` only                                    | Rule #1 — không verify ACTUAL behavior (click works?) | Verify click handler fires + state changes                            |
| 2   | Pixel position assertion `expect(getBoundingClientRect().x).toBe(120)` | Rule #3 — break trên viewport khác                    | Check CSS class / role / text instead                                 |
| 3   | Test AI-generated content quality                                      | Rule #4 — UI test only render, không content quality  | Content tests tách riêng (AI evaluation suite)                        |
| 4   | Hard-coded waits `await page.waitForTimeout(3000)`                     | Race condition + slow + Hook block                    | `waitForResponse`, `waitForSelector`, `expect.toBeVisible({timeout})` |
| 5   | Self-derived WCAG checks                                               | Rule #2 — chỉ test nếu design spec đòi                | Skip nếu spec không có                                                |

## More FE anti-patterns

| #   | Anti-pattern                                    | Fix                                                                                 |
| --- | ----------------------------------------------- | ----------------------------------------------------------------------------------- |
| 6   | `page.locator('div > div > span:nth-child(3)')` | Fragile selector. Dùng role/text/test-id                                            |
| 7   | Click bằng coordinates                          | Dùng `getByRole` / `getByText`                                                      |
| 8   | Inline locators duplicated                      | Centralize trong `src/selectors/*.selectors.ts`                                     |
| 9   | Auth state setup in each test                   | Use storage state (`global-setup.ts`) hoặc fixture                                  |
| 10  | `if (await elem.isVisible()) { expect... }`     | Conditional assertion (S-2 hook block) — guard via `toBeVisible()` directly         |
| 11  | Snapshot toàn page                              | Brittle. Snapshot component-level hoặc skip                                         |
| 12  | `data-testid` cho mọi element                   | Prefer semantic (`getByRole`, `getByLabel`). `testid` chỉ cho khi semantic không đủ |

## Anti-pattern: visibility-only (Rule #1)

❌ Cho có:

```ts
test('Submit button works', async ({ page }) => {
    await expect(page.getByRole('button', { name: 'Submit' })).toBeVisible();
    // PASS dù click có thể không work
});
```

✅ Verify actual behavior:

```ts
test('Submit button submits + shows success', async ({ page }) => {
    await page.getByLabel('Email').fill('test@x.com');
    await page.getByRole('button', { name: 'Submit' }).click();
    await expect(page.getByText('Saved')).toBeVisible(); // actual outcome
});
```

## Anti-pattern: pixel position (Rule #3)

❌:

```ts
const box = await page.locator('.header').boundingBox();
expect(box?.x).toBe(120); // breaks on different viewport
```

✅:

```ts
await expect(page.locator('.header')).toHaveCSS('position', 'sticky');
await expect(page.locator('.header')).toBeInViewport();
```

## Anti-pattern: hardcoded wait

❌ Hook `prevent-hardcoded-waits.sh` block:

```ts
await page.click('button');
await page.waitForTimeout(3000); // race condition
await expect(page.locator('.toast')).toBeVisible();
```

✅:

```ts
await page.click('button');
await expect(page.locator('.toast')).toBeVisible({ timeout: 5000 });
// or
const [response] = await Promise.all([page.waitForResponse('**/save'), page.click('button')]);
```

## Anti-pattern: self-derived WCAG (Rule #2)

❌:

```ts
// Tự suy "buttons must have aria-label" — design spec không nói
await expect(page.locator('button:not([aria-label])')).toHaveCount(0);
```

✅: chỉ check accessibility theo spec hoặc tách AT suite riêng.

## Anti-pattern: fragile selector

❌:

```ts
await page.locator('div.flex.flex-col > div:nth-child(3) > span').click();
```

✅:

```ts
await page.getByRole('button', { name: 'Continue' }).click();
// or
await page.locator('[data-testid="continue-btn"]').click();
```

## Hooks enforce (layer-1)

| Hook                                  | Block                                          |
| ------------------------------------- | ---------------------------------------------- |
| `prevent-hardcoded-waits.sh`          | `waitForTimeout(N)`                            |
| `verify-locator-strictness.sh`        | Locators không có `.first()` / strict mode     |
| `verify-no-conditional-assertions.sh` | `expect()` trong `if/else` block (S-2)         |
| `verify-test-patterns.sh`             | 8 generic anti-patterns (S-1..S-5, NP-1..NP-3) |
| `verify-pom-com-rules.sh`             | POM/Component pattern violations               |

## Checklist

```
☐ KHÔNG `toBeVisible()` only — verify ACTUAL behavior (Rule #1)
☐ KHÔNG pixel positions (Rule #3) — CSS/role/text instead
☐ KHÔNG test AI content quality trong UI test (Rule #4)
☐ KHÔNG `waitForTimeout(N)` — use `waitForResponse`/`toBeVisible({timeout})`
☐ KHÔNG self-derived WCAG (Rule #2) — chỉ theo design spec
☐ KHÔNG fragile selectors (nth-child, deep div chains)
☐ KHÔNG inline duplicated locators — centralize selectors
☐ KHÔNG conditional `expect` trong if/else (S-2)
☐ KHÔNG snapshot full page — component-level
☐ Hooks pass: prevent-hardcoded-waits · verify-test-patterns · verify-no-conditional-assertions
```

## See also

- [visual-states.md](./visual-states.md)
- [interactions.md](./interactions.md)
- [`/CLAUDE.md`](../../../../CLAUDE.md) Hooks section
- [`/_bmad-output/project-context.md`](../../../../_bmad-output/project-context.md) Anti-patterns S-1..S-5 / NP-1..NP-3
