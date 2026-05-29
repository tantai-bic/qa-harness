# E2E Patterns — Page Object Model + Component Object Model

> Layer cho E2E browser tests. Pair với [architecture](./architecture.md) + [helpers](./helpers.md) + [composable fixtures](#composable-fixture-pattern).

## Page Object Model (POM) — E2E mandatory

**Quy tắc:** 1 page = 1 class. Locators + page-level actions sống trong class, KHÔNG xuất hiện trong spec.

### ❌ BAD — locators rải rác trong spec

```typescript
test('login flow', async ({ page }) => {
    await page.goto('https://app.example.com/login');                  // hard-coded URL
    await page.locator('input[name="email"]').fill('user@test.com');   // raw selector
    await page.locator('input[name="password"]').fill('Pass123!');     // raw selector
    await page.locator('button:has-text("Sign in")').click();          // brittle text selector
    await page.waitForURL('**/dashboard');                              // implicit wait
    await expect(page.locator('.user-menu')).toBeVisible();             // CSS class brittle
});
```
Hệ quả: UI đổi `placeholder` / class → 50 test fail; KHÔNG reuse được khi 10 test cùng login.

### ✅ GOOD — POM encapsulation

```typescript
// src/pages/login.page.ts
import type { Page, Locator } from '@playwright/test';
import { ROUTES } from '@src/constants/routes.constants';

export class LoginPage {
    readonly emailInput: Locator;
    readonly passwordInput: Locator;
    readonly submitButton: Locator;
    readonly errorBanner: Locator;

    constructor(private readonly page: Page) {
        this.emailInput    = page.getByRole('textbox', { name: /email/i });
        this.passwordInput = page.getByRole('textbox', { name: /password/i });
        this.submitButton  = page.getByRole('button', { name: /sign in/i });
        this.errorBanner   = page.getByRole('alert');
    }

    async goto() {
        await this.page.goto(ROUTES.LOGIN);
    }

    async loginAs(credentials: { email: string; password: string }) {
        await this.emailInput.fill(credentials.email);
        await this.passwordInput.fill(credentials.password);
        await this.submitButton.click();
    }

    async expectLoggedIn() {
        await this.page.waitForURL(ROUTES.DASHBOARD);
    }

    async expectError(message: string | RegExp) {
        await this.errorBanner.waitFor({ state: 'visible' });
        await this.errorBanner.filter({ hasText: message }).waitFor();
    }
}
```

```typescript
// tests/e2e/auth/P0-login.spec.ts
test('login happy path', async ({ page }) => {
    const login = new LoginPage(page);
    await login.goto();
    await login.loginAs(testUser);
    await login.expectLoggedIn();
});
```

### POM rules

| Rule | Lý do |
|------|-------|
| 1 file = 1 page = 1 class | Mapping clear với URL |
| Locators khai báo trong `constructor` (readonly) | Lazy-eval (locator KHÔNG query DOM khi tạo), dễ inspect |
| Ưu tiên `getByRole` / `getByLabel` / `getByTestId` — TRÁNH CSS/XPath | Stable với UI refactor; reflect user intent |
| Action method tên động từ (`loginAs`, `submitForm`) | Đọc spec hiểu intent ngay |
| Assertion method `expect*` (`expectLoggedIn`, `expectError`) | Encapsulate complex assertion |
| KHÔNG return `Page` từ method | Page lifecycle thuộc fixture |
| KHÔNG hard-code URL — dùng `ROUTES.X` constant | Đổi env 1 chỗ |
| KHÔNG call `page.waitForTimeout(n)` — dùng `Locator.waitFor` / `expect.toBeVisible` | Flaky test |

## Component Object Model (COM) — reusable UI

**Khi nào dùng COM thay vì POM:** UI element xuất hiện ở ≥ 2 page (header, sidebar, modal, table, form). Tách ra để 1 nơi maintain.

### ❌ BAD — duplicate header logic trong nhiều POM

```typescript
// dashboard.page.ts
async openProfileMenu() {
    await this.page.locator('[data-testid="user-avatar"]').click();
    await this.page.locator('text=Profile').click();
}

// settings.page.ts — DUPLICATE
async openProfileMenu() {
    await this.page.locator('[data-testid="user-avatar"]').click();
    await this.page.locator('text=Profile').click();
}
```

### ✅ GOOD — COM composition

```typescript
// src/components/app-header.component.ts
import type { Page, Locator } from '@playwright/test';

export class AppHeaderComponent {
    readonly userAvatar: Locator;
    readonly notificationBell: Locator;

    constructor(private readonly page: Page) {
        this.userAvatar       = page.getByTestId('user-avatar');
        this.notificationBell = page.getByTestId('notification-bell');
    }

    async openProfileMenu() {
        await this.userAvatar.click();
        await this.page.getByRole('menuitem', { name: 'Profile' }).click();
    }

    async expectUnreadCount(n: number) {
        await this.notificationBell.locator('.badge').waitFor();
        const text = await this.notificationBell.locator('.badge').textContent();
        if (Number(text) !== n) throw new Error(`Expected ${n}, got ${text}`);
    }
}
```

```typescript
// src/pages/dashboard.page.ts — compose component
import { AppHeaderComponent } from '@src/components/app-header.component';

export class DashboardPage {
    readonly header: AppHeaderComponent;
    readonly summaryCard: Locator;

    constructor(private readonly page: Page) {
        this.header      = new AppHeaderComponent(page);
        this.summaryCard = page.getByTestId('summary-card');
    }

    async goto() { await this.page.goto(ROUTES.DASHBOARD); }
}
```

```typescript
test('navigate profile from dashboard', async ({ page }) => {
    const dashboard = new DashboardPage(page);
    await dashboard.goto();
    await dashboard.header.openProfileMenu();   // ← reuse component action
});
```

### COM rules

- COM scope = **1 UI region** (header, modal, form, table). KHÔNG cover toàn page.
- COM nhận `page` HOẶC parent `locator` qua constructor — KHÔNG tự `new Page`.
- Page compose component qua field: `readonly header = new AppHeaderComponent(this.page)`.
- Component CÓ THỂ chứa component khác (vd `LoginFormComponent` chứa `PasswordFieldComponent`).
- COM tuyệt đối KHÔNG import POM (tránh circular dep).

### Locator strategy priority (POM + COM)

```
1. page.getByRole(...)              ← user-facing, accessible
2. page.getByLabel(...)             ← form fields
3. page.getByPlaceholder(...)       ← input hints
4. page.getByText(...)              ← visible content (exact match recommended)
5. page.getByTestId('xxx')          ← data-testid="xxx" (stable, dev-controlled)
6. page.locator('css/xpath')        ← LAST RESORT — brittle
```

CSS/XPath chỉ dùng khi 1-5 không khả thi (vd component không có role/label/testid). Khi buộc dùng CSS → lưu selector vào `constants/selectors.ts`.

## Composable Fixture Pattern

Fixture gộp setup layer (API state seed) + UI layer (POM init). Test chỉ cần destructure đúng cái cần.

### ❌ BAD — setup trong test body

```typescript
test('user can edit profile', async ({ request, page }) => {
    // SETUP API state inline (lặp ở 20 test)
    const signup = await request.post(API_ENDPOINTS.AUTH.SIGNUP, { data: createSignupPayload() });
    const { accessToken } = await signup.json();
    await page.context().addCookies([{ name: 'token', value: accessToken, url: 'https://app.test' }]);
    // SETUP POM inline (lặp ở 20 test)
    const profile = new ProfilePage(page);
    await profile.goto();
    // ACTUAL test
    await profile.updateBio('new bio');
    await profile.expectSaved();
});
```

### ✅ GOOD — composable fixture

```typescript
// src/fixtures/profile.fixture.ts
import { test as base } from '@playwright/test';
import { authedSession } from './auth.fixture';
import { ProfilePage } from '@src/pages/profile.page';

type Fixtures = {
    authedSession: { accessToken: string; userId: string };
    profilePage: ProfilePage;
};

export const test = base.extend<Fixtures>({
    authedSession,  // composed: signup + cookie injection + cleanup
    profilePage: async ({ page, authedSession }, use) => {
        const profile = new ProfilePage(page);
        await profile.goto();
        await use(profile);
        // no teardown — authedSession fixture handles user cleanup
    },
});

export { expect } from '@playwright/test';
```

```typescript
// test — destructure đúng cái cần, không setup
import { test, expect } from '@src/fixtures/profile.fixture';

test('user can edit profile', async ({ profilePage }) => {
    await profilePage.updateBio('new bio');
    await profilePage.expectSaved();
});
```

### Fixture composition rules

- 1 fixture = 1 concern (auth, profile data, mock campaign, ...)
- Fixture composable: `profilePage` depends on `authedSession` → Playwright tự resolve order
- Cleanup PHẢI idempotent (gọi 2 lần không lỗi)
- Cleanup wrap trong `try/catch` để 1 fixture fail KHÔNG block fixture khác cleanup
- Fixture KHÔNG được mutate global state (no `process.env.X = ...`)
