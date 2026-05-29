# Frontend — Visual States

UI test coverage cho 9 visual states + responsive.

## 9 visual states

| State        | Khi nào hiện              | Test                                                      |
| ------------ | ------------------------- | --------------------------------------------------------- |
| **Default**  | Initial render            | Render text/element visible                               |
| **Hover**    | Mouse over                | CSS hover class applied · cursor change                   |
| **Focus**    | Tab/click focus           | Outline/ring visible · keyboard accessible                |
| **Active**   | Mouse-down / pressed      | CSS active class · visual feedback                        |
| **Disabled** | `disabled` attr/prop      | Cursor not-allowed · click blocked · opacity reduced      |
| **Error**    | Invalid input / API error | Error message visible · field red border · retry CTA      |
| **Loading**  | Async pending             | Skeleton/spinner visible · UI not flash · button disabled |
| **Empty**    | `data: []`                | "No results" message · NOT spinner mãi                    |
| **Success**  | Action completed          | Toast / inline confirmation · state updated               |

## Responsive viewports

| Viewport      | Width   | Use case                   |
| ------------- | ------- | -------------------------- |
| Mobile small  | 320     | iPhone SE, smallest target |
| Mobile        | 375-414 | iPhone/Android common      |
| Tablet        | 768     | iPad portrait              |
| Desktop       | 1280    | Laptop common              |
| Desktop large | 1920    | Full HD monitor            |

Test theo design spec — KHÔNG tự suy breakpoints.

## Pattern: state coverage

```ts
test.describe('Submit button states', () => {
    test('[default] button enabled with text "Submit"', async ({ page }) => {
        await expect(page.getByRole('button', { name: 'Submit' })).toBeEnabled();
    });

    test('[loading] click → button shows spinner + disabled', async ({ page }) => {
        await page.getByRole('button', { name: 'Submit' }).click();
        await expect(page.locator('[data-testid="submit-spinner"]')).toBeVisible();
        await expect(page.getByRole('button', { name: 'Submit' })).toBeDisabled();
    });

    test('[success] after submit → toast "Saved"', async ({ page }) => {
        await page.getByRole('button', { name: 'Submit' }).click();
        await expect(page.getByText('Saved')).toBeVisible();
    });

    test('[error] API fail → inline error visible', async ({ page }) => {
        // mock 500
        await page.route('**/save', (r) => r.fulfill({ status: 500 }));
        await page.getByRole('button', { name: 'Submit' }).click();
        await expect(page.getByText(/error|failed/i)).toBeVisible();
    });
});
```

## Pattern: empty state

```ts
test('[empty] no campaigns → "Create your first campaign"', async ({ page }) => {
    await page.route('**/campaigns', (r) => r.fulfill({ status: 200, body: JSON.stringify({ data: [] }) }));
    await page.goto('/dashboard');
    await expect(page.getByText('Create your first campaign')).toBeVisible();
    await expect(page.locator('[data-testid="campaigns-list"] > *')).toHaveCount(0);
});
```

## Responsive checklist

```
☐ Viewport 320 — content fits, no horizontal scroll
☐ Viewport 768 — tablet layout (if design has one)
☐ Viewport 1280 — desktop layout
☐ Critical CTAs reachable trong mọi viewport
☐ Image / hero responsive (no overflow)
☐ Modal width adapt
```

## Tools

| Tool                                                      | Mục đích               |
| --------------------------------------------------------- | ---------------------- |
| Playwright `page.setViewportSize({width, height})`        | Test specific viewport |
| Playwright `expect(...).toHaveScreenshot()`               | Visual regression      |
| MCP `mcp__plugin_playwright_playwright__browser_resize`   | Debug FE responsive    |
| MCP `mcp__plugin_playwright_playwright__browser_snapshot` | Inspect DOM state      |

## Checklist (visual states)

```
☐ Visual state covered: default, hover, focus, active, disabled, error, loading, empty, success
☐ Responsive: tested 320 / 768 / 1280 viewports
☐ Empty data state message present (NOT spinner mãi)
☐ Error state user-friendly + retry path
☐ Loading state visible khi pending (no UI flash)
☐ Success feedback (toast/inline)
☐ Disabled state: cursor not-allowed + click blocked
☐ Theo design spec — KHÔNG tự suy WCAG/Material
```

## See also

- [interactions.md](./interactions.md) — form, modal, keyboard
- [anti-patterns.md](./anti-patterns.md) — FE anti-patterns
- Project: `src/selectors/*.selectors.ts` (POM pattern)
