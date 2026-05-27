# Helpers + Logger — Pure Utilities

> Helpers là layer dưới cùng — pure, no state. Logger là utility xuyên suốt cho traceability.

## Helper Pattern — pure utility

**Định nghĩa:** function pure (input → output), KHÔNG state, KHÔNG side effect lên DOM/network trừ khi đó là chính purpose (vd `waitForApiResponse`).

### Phân loại helper

| Loại | Vị trí | Ví dụ |
|------|--------|-------|
| Wait helpers | `helpers/wait.helper.ts` | `waitForApiResponse`, `waitForToast` |
| Format helpers | `helpers/format.helper.ts` | `formatCurrency`, `parseISODate` |
| Assertion helpers | `helpers/assert.helper.ts` | `expectArrayContainsObject`, `expectWithinRange` |
| Network helpers | `helpers/network.helper.ts` | `mockApiResponse`, `interceptRequest` |
| File I/O helpers | `helpers/file.helper.ts` | `loadFixtureJson`, `compareScreenshot` |
| Logger | `helpers/logger.helper.ts` | `TestLogger` singleton |

### ❌ BAD — inline duplicate logic

```typescript
test('check creator earnings', async ({ page }) => {
    await page.getByTestId('earnings').click();
    // duplicate wait logic
    for (let i = 0; i < 30; i++) {
        const text = await page.getByTestId('earnings-value').textContent();
        if (text && text !== '--') break;
        await page.waitForTimeout(1000);  // 🚨 polling với setTimeout
    }
    const raw = await page.getByTestId('earnings-value').textContent();
    // duplicate format logic
    const amount = parseFloat(raw!.replace(/[$,]/g, ''));
    expect(amount).toBeGreaterThan(0);
});
```

### ✅ GOOD — helper extraction

```typescript
// src/helpers/wait.helper.ts
import type { Locator } from '@playwright/test';

export async function waitForNonPlaceholder(locator: Locator, placeholder = '--', timeoutMs = 30_000) {
    await locator.waitFor({ state: 'visible' });
    await locator.evaluate(
        (el, ph) => new Promise<void>((resolve, reject) => {
            const obs = new MutationObserver(() => {
                if (el.textContent && el.textContent.trim() !== ph) { obs.disconnect(); resolve(); }
            });
            obs.observe(el, { childList: true, characterData: true, subtree: true });
            if (el.textContent && el.textContent.trim() !== ph) { obs.disconnect(); resolve(); }
            setTimeout(() => { obs.disconnect(); reject(new Error('timeout')); }, 30_000);
        }),
        placeholder,
    );
}
```

```typescript
// src/helpers/format.helper.ts
export function parseCurrency(raw: string): number {
    const cleaned = raw.replace(/[^\d.-]/g, '');
    const n = Number(cleaned);
    if (Number.isNaN(n)) throw new Error(`Cannot parse currency: "${raw}"`);
    return n;
}
```

```typescript
// tests/e2e/...spec.ts — gọn, intent rõ
test('check creator earnings', async ({ page }) => {
    const earningsValue = page.getByTestId('earnings-value');
    await page.getByTestId('earnings').click();
    await waitForNonPlaceholder(earningsValue);
    const amount = parseCurrency((await earningsValue.textContent())!);
    expect(amount).toBeGreaterThan(0);
});
```

### Helper rules

- Helper PHẢI là **pure** hoặc declare side effect rõ trong tên (`mockX`, `interceptX`)
- KHÔNG import `pages/` hoặc `components/` (helper là layer dưới)
- KHÔNG dùng `page.waitForTimeout(n)` — dùng condition-based wait
- 1 helper file = 1 responsibility group (wait / format / assert / network)
- Helper trả về Promise rõ — KHÔNG fire-and-forget trừ khi đó là intent (vd `prewarmCache`)

## Logger format

```
🧪 [P0] Test name
   [POST] https://api-stg.example.com/auth/signup
   📋 {"email":"test_...","password":"..."}
   📥 Expected: 201 | Actual: 201 → ✅ PASS
```

```typescript
import { TestLogger } from '@src/utils/test-logger';
const logger = TestLogger.getInstance();
logger.info(`🧪 ${testName}`);
```
