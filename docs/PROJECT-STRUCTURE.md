# SprouX Testing - Project Structure Guide

> Tài liệu mô tả cấu trúc project để team members dễ dàng hiểu và làm việc.

**Last Updated:** 2026-01-06
**Framework:** Playwright 1.48.0 + TypeScript 5.3.3

---

## Tổng quan

**sprouX-testing** là framework test automation cho sprouX API, sử dụng Playwright + TypeScript. Project được tổ chức theo mô hình **modular** với sự tách biệt rõ ràng giữa:

- **Source code** (`src/`) - Utilities, services, factories
- **Test specs** (`tests/`) - Test cases thực tế
- **Documentation** (`docs/`) - Tài liệu dự án

---

## Sơ đồ cấu trúc thư mục

```
sprouX-testing/
│
├── src/                          # 🔧 SOURCE UTILITIES
│   ├── auth/                     # Module Authentication
│   ├── refinement/               # Module Refinement (AI Conversation)
│   ├── config/                   # Cấu hình API
│   ├── constants/                # Hằng số (endpoints, HTTP status)
│   ├── factories/                # Data factories (faker-based)
│   ├── fixtures/                 # Playwright fixtures
│   ├── utils/                    # Tiện ích chung
│   └── index.ts                  # Re-export tất cả modules
│
├── tests/                        # 🧪 TEST SPECIFICATIONS
│   ├── api/                      # API tests (không browser)
│   │   ├── auth/                 # Tests cho Authentication
│   │   └── conversation/         # Tests cho AI Conversation
│   │       └── phase1/           # Phase 1 - Stories
│   │           ├── story-02.1.1-*/
│   │           ├── story-02.1.2-*/
│   │           └── ...
│   └── e2e/                      # E2E tests (có browser)
│
├── docs/                         # 📚 DOCUMENTATION
│   ├── api/                      # API documentation
│   ├── sprint2/                  # Sprint 2 stories & bugs
│   ├── sprint3/                  # Sprint 3 stories & bugs
│   └── templates/                # Templates (bug log, test report)
│
├── scripts/                      # 🛠️ Helper scripts
├── .husky/                       # Git hooks (pre-commit)
├── .github/workflows/            # CI/CD workflows
├── _bmad/                        # BMAD Method framework
│
├── playwright.config.ts          # Cấu hình Playwright
├── tsconfig.json                 # Cấu hình TypeScript
├── eslint.config.mjs             # Cấu hình ESLint
├── .prettierrc                   # Cấu hình Prettier
├── package.json                  # Dependencies & scripts
└── .env                          # Environment variables
```

---

## Kiến trúc `src/` - Giải thích cho người mới

> **Ví von dễ hiểu:** Hãy tưởng tượng `src/` như một **nhà hàng**:
>
> - **Types** = Menu (liệt kê món ăn và mô tả)
> - **Factory** = Bếp (nấu món ăn theo công thức)
> - **Service** = Phục vụ (nhận order, giao món, ghi bill)
> - **Constants** = Địa chỉ & SĐT nhà hàng (thông tin cố định)

---

### 🎬 Flow thực tế: "Tạo session và trả lời câu hỏi 1"

Hãy xem các thành phần hoạt động như thế nào khi chạy 1 test case thực tế:

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║  TÌNH HUỐNG: Test "Tạo session mới và trả lời câu hỏi 1"                      ║
╚═══════════════════════════════════════════════════════════════════════════════╝

┌─────────────────────────────────────────────────────────────────────────────────┐
│  BƯỚC 1: Bạn viết TEST (P0-conversation-flow.spec.ts)                          │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   test('Trả lời Q1 thành công', async ({ request, session }) => {              │
│       const result = await RefinementService.submitResponse(                    │
│           request,                                                              │
│           session.sessionId,    // ← session có sẵn từ fixture                 │
│           session.accessToken,                                                  │
│           'Tôi muốn tạo app học tiếng Anh',   // ← câu trả lời                 │
│           'Test Q1'                                                             │
│       );                                                                        │
│       expect(result.currentQuestion).toBe(2);  // ← chuyển sang Q2             │
│   });                                                                           │
│                                                                                 │
│   💭 Test chỉ gọi Service, không biết URL hay cách gọi API                     │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        │ gọi
                                        ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  BƯỚC 2: SERVICE xử lý (refinement.service.ts)                                 │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│   export async function submitResponse(request, sessionId, token, answer) {    │
│                                                                                 │
│       // 1️⃣ Lấy URL từ CONSTANTS                                               │
│       const url = API_ENDPOINTS.REFINEMENT.RESPOND(sessionId);                 │
│       // → "https://sproux-api.beincom.app/refinements/abc123/respond"         │
│                                                                                 │
│       // 2️⃣ Tạo payload theo TYPES                                             │
│       const payload = { response: answer };                                    │
│       // → { response: "Tôi muốn tạo app học tiếng Anh" }                      │
│                                                                                 │
│       // 3️⃣ Gọi API và log                                                     │
│       logger.log('[POST] ' + url);                                             │
│       const response = await request.post(url, { data: payload, headers });    │
│       logger.log('Status: 201 ✅');                                            │
│                                                                                 │
│       return response.json();                                                  │
│   }                                                                             │
│                                                                                 │
│   💭 Service biết cách gọi API, thêm headers, log request/response             │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
                    │                               │
         lấy URL   │                               │ kiểm tra format
                    ▼                               ▼
┌───────────────────────────────┐   ┌───────────────────────────────┐
│  CONSTANTS (api.constants.ts) │   │  TYPES (refinement.types.ts)  │
├───────────────────────────────┤   ├───────────────────────────────┤
│                               │   │                               │
│  REFINEMENT: {                │   │  interface SubmitResult {     │
│    RESPOND: (sessionId) =>    │   │    currentQuestion: number;   │
│      `/refinements/           │   │    status: string;            │
│       ${sessionId}/respond`   │   │    messages: Message[];       │
│  }                            │   │  }                            │
│                               │   │                               │
│  💭 Chứa tất cả URLs          │   │  💭 Mô tả data trả về         │
│                               │   │                               │
└───────────────────────────────┘   └───────────────────────────────┘


╔═══════════════════════════════════════════════════════════════════════════════╗
║  KẾT QUẢ CHẠY TEST                                                            ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║                                                                               ║
║  🧪 Test Q1                                                                   ║
║     [POST] https://sproux-api.beincom.app/refinements/abc123/respond          ║
║     📋 {"response":"Tôi muốn tạo app học tiếng Anh"}                          ║
║     📥 Expected: 201 | Actual: 201 → ✅ PASS                                  ║
║                                                                               ║
║  ✓ Trả lời Q1 thành công (1.2s)                                              ║
║                                                                               ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

---

### 🍜 So sánh với nhà hàng

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         🍜 NHÀ HÀNG PHỞ                                        │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  KHÁCH (Test)                                                                   │
│     │                                                                           │
│     │ "Cho tôi 1 tô phở bò tái"                                                │
│     ▼                                                                           │
│  PHỤC VỤ (Service)                                                             │
│     │                                                                           │
│     ├──→ Xem MENU (Types): "Phở bò tái có: bánh phở, thịt bò, hành, giá..."   │
│     │                                                                           │
│     ├──→ Gọi BẾP (Factory): "Làm 1 tô phở bò tái"                             │
│     │         │                                                                 │
│     │         └──→ Bếp nấu theo công thức, mỗi tô hơi khác (unique)           │
│     │                                                                           │
│     ├──→ Tra ĐỊA CHỈ BẾP (Constants): Bếp ở tầng 2, quầy số 3                 │
│     │                                                                           │
│     └──→ Mang phở ra cho khách + ghi bill (logging)                           │
│                                                                                 │
│  KHÁCH nhận phở, không cần biết:                                               │
│     - Bếp ở đâu (URL)                                                          │
│     - Nấu như thế nào (API call)                                               │
│     - Công thức ra sao (payload format)                                        │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                         💻 TEST AUTOMATION                                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                 │
│  TEST (P0-conversation-flow.spec.ts)                                           │
│     │                                                                           │
│     │ "Gọi submitResponse với answer = 'App học tiếng Anh'"                    │
│     ▼                                                                           │
│  SERVICE (refinement.service.ts)                                               │
│     │                                                                           │
│     ├──→ Xem TYPES: "SubmitResult có: currentQuestion, status, messages..."   │
│     │                                                                           │
│     ├──→ Gọi FACTORY (nếu cần tạo data phức tạp)                              │
│     │         │                                                                 │
│     │         └──→ Factory tạo data unique mỗi lần chạy                       │
│     │                                                                           │
│     ├──→ Tra CONSTANTS: URL = /refinements/{sessionId}/respond                │
│     │                                                                           │
│     └──→ Gọi API + log request/response                                       │
│                                                                                 │
│  TEST nhận kết quả, không cần biết:                                            │
│     - URL là gì (Constants lo)                                                 │
│     - Payload format (Service lo)                                              │
│     - Data tạo như thế nào (Factory lo)                                        │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

### 📊 Tóm tắt: Ai làm gì?

| Thành phần    | Vai trò                                         | Ví dụ thực tế                            |
| ------------- | ----------------------------------------------- | ---------------------------------------- |
| **Test**      | Khách hàng - chỉ order và nhận kết quả          | `expect(result.currentQuestion).toBe(2)` |
| **Service**   | Phục vụ - nhận order, điều phối, giao hàng      | `submitResponse()`, `startSession()`     |
| **Constants** | Danh bạ - lưu địa chỉ các endpoint              | `API_ENDPOINTS.REFINEMENT.RESPOND`       |
| **Types**     | Menu - mô tả món ăn (data) trông như thế nào    | `interface SubmitResult { ... }`         |
| **Factory**   | Bếp - nấu món (tạo data) theo công thức         | `createSignupPayload()`                  |
| **Fixtures**  | Setup bàn - chuẩn bị sẵn đồ trước khi khách đến | `session` fixture tự tạo session         |

---

### Tại sao phải tách ra nhiều file như vậy?

**Câu hỏi hay gặp:** "Sao không viết hết vào 1 file cho đơn giản?"

**Trả lời:** Vì khi project lớn lên (50-100 tests), bạn sẽ gặp vấn đề:

| Viết 1 file                                | Vấn đề gặp phải                                             |
| ------------------------------------------ | ----------------------------------------------------------- |
| Gõ URL trực tiếp `'/auth/login'`           | Backend đổi thành `'/api/v2/auth/login'` → phải sửa 50 chỗ! |
| Gõ data trực tiếp `email: 'test@test.com'` | Chạy test lần 2 → lỗi "email đã tồn tại"                    |
| Copy-paste code gọi API                    | Sửa 1 chỗ quên sửa chỗ khác → bug                           |

**Giải pháp:** Tách ra các file nhỏ, mỗi file 1 nhiệm vụ. Sửa 1 chỗ = tất cả tests tự động cập nhật.

---

## Giải thích từng loại file (dùng ví dụ thật từ project)

### 📘 File `.types.ts` - "Bản mô tả" data

**Nó là gì?** Là file mô tả "data trông như thế nào".

**Ví von:** Giống như **menu nhà hàng** - liệt kê tên món, mô tả, giá tiền. Bạn nhìn vào menu để biết có thể order gì.

**File thật trong project:** `src/refinement/refinement.types.ts`

```typescript
// Mô tả: "Session trông như thế nào?"
export interface RefinementSession {
    sessionId: string; // Mã session (VD: "abc-123")
    currentQuestion: number; // Đang ở câu hỏi số mấy (1-7)
    answeredQuestions: number; // Đã trả lời bao nhiêu câu
    status: string; // Trạng thái: 'active', 'completed', ...
}
```

**Lợi ích cho người mới:**

```typescript
// Khi bạn gõ code, VS Code sẽ tự gợi ý:
// Nếu gõ sai, VS Code báo lỗi ngay (không cần chạy test mới biết):
session.session.sesionId; // Gõ dấu chấm → hiện ra: sessionId, currentQuestion, answeredQuestions, status // ❌ Gạch đỏ: "Did you mean 'sessionId'?"
```

**Tóm lại:** Types giúp VS Code "hiểu" data của bạn, từ đó gợi ý và bắt lỗi chính tả.

---

### 🏭 File `.factory.ts` - "Máy tạo data test"

**Nó là gì?** Là file chứa function tạo data test tự động.

**Ví von:** Giống như **bếp nhà hàng** - bạn order "Phở bò" thì bếp tự nấu, không cần bạn tự vào bếp làm.

**Vấn đề nếu không có factory:**

```typescript
// ❌ Viết thẳng data vào test
test('Đăng ký tài khoản', async () => {
    const data = {
        email: 'test@gmail.com', // Chạy lần 1: OK
        password: 'Test123!', // Chạy lần 2: LỖI! Email đã tồn tại!
        fullName: 'Nguyen Van A',
    };
});
```

**Với factory:**

```typescript
// ✅ Factory tự tạo email khác nhau mỗi lần chạy
import { createSignupPayload } from '@src/auth/signup/signup.factory';

test('Đăng ký tài khoản', async () => {
    const data = createSignupPayload();
    // Lần 1: { email: 'test_1704067200000_abc@example.com', ... }
    // Lần 2: { email: 'test_1704067200001_xyz@example.com', ... }
    // → Mỗi lần khác nhau, không bao giờ trùng!
});
```

**Tóm lại:** Factory giúp tạo data test tự động, không bao giờ trùng nhau.

---

### ⚙️ File `.service.ts` - "Người phục vụ" gọi API

**Nó là gì?** Là file chứa function gọi API và in log.

**Ví von:** Giống như **phục vụ nhà hàng** - bạn gọi "Cho tôi phở bò", phục vụ đi xuống bếp lấy và mang lên cho bạn. Bạn không cần biết bếp ở đâu, nấu như thế nào.

**Vấn đề nếu gọi API trực tiếp trong test:**

```typescript
// ❌ Gọi API trực tiếp trong test
test('Tạo session', async ({ request }) => {
    const response = await request.post('https://sproux-api.beincom.app/refinements/start', {
        headers: { Authorization: 'Bearer xxx' },
    });
    // Vấn đề:
    // 1. URL dài, dễ gõ sai
    // 2. Không có log khi fail
    // 3. Copy-paste sang test khác → nhân đôi code
});
```

**Với service:**

```typescript
// ✅ Gọi qua service - ngắn gọn, có log
import { RefinementService } from '@src/refinement';

test('Tạo session', async ({ request, accessToken }) => {
    const session = await RefinementService.startSession(request, accessToken, 'Tạo session');
    // Service tự động:
    // 1. Gọi đúng URL
    // 2. Thêm headers
    // 3. In log ra terminal
});
```

**Log tự động hiện ra:**

```
🧪 Tạo session
   [POST] https://sproux-api.beincom.app/refinements/start
   📥 Expected: 201 | Actual: 201 → ✅ PASS
```

**Tóm lại:** Service giúp gọi API dễ dàng và có log để debug khi fail.

---

### 📍 File `api.constants.ts` - "Danh bạ" các URL

**Nó là gì?** Là file chứa tất cả URL API.

**Ví von:** Giống như **danh bạ điện thoại** - muốn gọi ai thì tra danh bạ, không cần nhớ số.

**File thật trong project:** `src/constants/api.constants.ts`

```typescript
export const API_ENDPOINTS = {
    AUTH: {
        LOGIN: 'https://sproux-api.beincom.app/auth/login',
        SIGNUP: 'https://sproux-api.beincom.app/auth/signup',
    },
    REFINEMENT: {
        START: 'https://sproux-api.beincom.app/refinements/start',
        RESPOND: (sessionId) => `https://sproux-api.beincom.app/refinements/${sessionId}/respond`,
    },
};
```

**Lợi ích:**

```typescript
// Thay vì nhớ URL dài
await request.post('https://sproux-api.beincom.app/refinements/start');

// Chỉ cần gõ
await request.post(API_ENDPOINTS.REFINEMENT.START);
// VS Code tự gợi ý khi gõ API_ENDPOINTS.
```

**Khi backend đổi URL:** Chỉ sửa 1 file `api.constants.ts` → tất cả 75 tests tự động dùng URL mới.

**Tóm lại:** Constants giúp quản lý URL tập trung, đổi 1 chỗ = đổi tất cả.

---

### 🔌 File `fixtures/` - "Chuẩn bị sẵn" cho test

**Nó là gì?** Là file setup sẵn những thứ test cần (như session, token).

**Ví von:** Giống như **bàn ăn đã setup sẵn** - khi bạn đến, đĩa/muỗng/đũa đã có sẵn, ăn xong có người dọn.

**File thật:** `src/fixtures/refinement.fixture.ts`

```typescript
// Fixture tự động tạo session TRƯỚC mỗi test
// và tự động dọn dẹp SAU mỗi test
export const test = base.extend({
    session: async ({ request, accessToken }, use) => {
        // 🟢 TRƯỚC TEST: Tạo session mới
        const session = await RefinementService.startSession(request, accessToken);

        // Truyền session cho test dùng
        await use(session);

        // 🔴 SAU TEST: Tự động dọn dẹp (kể cả khi test fail)
        await RefinementService.abandonSession(request, session.sessionId, accessToken);
    },
});
```

**Sử dụng trong test:**

```typescript
// Không cần tạo session, fixture đã lo
test('Trả lời câu hỏi 1', async ({ request, session }) => {
    // session đã có sẵn, dùng luôn!
    console.log(session.sessionId); // "abc-123"
});
// → Test xong, session tự động bị xóa
```

**Tóm lại:** Fixtures giúp setup/cleanup tự động, test chỉ cần tập trung vào logic.

---

## Tổng kết: Mỗi file làm gì?

| File               | Nhiệm vụ                     | Ví von             |
| ------------------ | ---------------------------- | ------------------ |
| `.types.ts`        | Mô tả data trông như thế nào | Menu nhà hàng      |
| `.factory.ts`      | Tạo data test tự động        | Bếp nấu món        |
| `.service.ts`      | Gọi API + in log             | Phục vụ bàn        |
| `api.constants.ts` | Lưu các URL                  | Danh bạ điện thoại |
| `fixtures/`        | Setup/cleanup tự động        | Bàn ăn setup sẵn   |

---

## Sơ đồ quan hệ giữa các files (cho người thích hình ảnh)

```
Bạn viết TEST → TEST gọi SERVICE → SERVICE lấy URL từ CONSTANTS
                                 → SERVICE dùng FACTORY tạo data
                                 → FACTORY dùng TYPES để biết data gồm gì

Tóm lại:
┌──────────────┐
│  TEST FILE   │  ← Bạn viết code ở đây
│ (.spec.ts)   │
└──────┬───────┘
       │ gọi
       ▼
┌──────────────┐
│   SERVICE    │  ← Gọi API, in log
│(.service.ts) │
└──────┬───────┘
       │ dùng
       ▼
┌──────────────┬──────────────┬──────────────┐
│  CONSTANTS   │   FACTORY    │    TYPES     │
│  (URLs)      │  (tạo data)  │  (mô tả data)│
└──────────────┴──────────────┴──────────────┘
```

---

## Quy tắc cho người mới

### ✅ NÊN làm:

1. **Gọi API qua Service** - không gọi trực tiếp `request.post()`
2. **Dùng Factory tạo data** - không gõ data cứng vào test
3. **Dùng API_ENDPOINTS** - không gõ URL trực tiếp

### ❌ KHÔNG NÊN làm:

```typescript
// ❌ Gọi API trực tiếp
await request.post('https://sproux-api.beincom.app/refinements/start');

// ❌ Gõ data cứng
const data = { email: 'test@test.com', password: '123456' };

// ❌ Gõ URL cứng
await request.post('/refinements/' + sessionId + '/respond');
```

### ✅ NÊN làm:

```typescript
// ✅ Gọi qua Service
await RefinementService.startSession(request, accessToken, testName);

// ✅ Dùng Factory
const data = createSignupPayload();

// ✅ Dùng Constants
await request.post(API_ENDPOINTS.REFINEMENT.RESPOND(sessionId));
```

---

## Hướng dẫn thực tế: Khi nào sửa file nào trong `src/`?

> **Dành cho người mới:** Đây là các tình huống thực tế bạn sẽ gặp khi làm việc. Mỗi tình huống chỉ cần sửa 1-2 file.

---

### 🔧 Tình huống 1: Backend đổi Base URL

**Ví dụ:** URL API đổi từ `https://sproux-api.beincom.app` sang `https://api-v2.sproux.com`

**File cần sửa:** `src/utils/env-config.ts` hoặc `.env`

#### Cách 1: Sửa file `.env` (đơn giản nhất)

```env
# Trước
API_URL=https://sproux-api.beincom.app

# Sau
API_URL=https://api-v2.sproux.com
```

#### Cách 2: Sửa env-config.ts (thêm môi trường mới)

```typescript
// src/utils/env-config.ts

const ENV_URL_MAP = {
    stg: 'https://sproux-api.beincom.app', // Staging
    rel: 'https://sproux-api.beincom.biz', // Release
    prod: 'https://api.sproux.com', // Production
    v2: 'https://api-v2.sproux.com', // ← THÊM MỚI
};
```

Sau đó chạy test với môi trường mới:

```bash
TEST_ENV=v2 npx playwright test --project=api
```

**Không cần sửa:** Tests, Services, Constants - tất cả tự động dùng URL mới!

---

### 🔧 Tình huống 2: Backend đổi Endpoint Path

**Ví dụ:** Endpoint đổi từ `/refinements/start` sang `/api/v2/refinements/start`

**File cần sửa:** `src/constants/api.constants.ts` (chỉ 1 file!)

```typescript
// src/constants/api.constants.ts

// TRƯỚC
export const REFINEMENT_BASE = `${BASE_API_URL}/refinements`;

// SAU
export const REFINEMENT_BASE = `${BASE_API_URL}/api/v2/refinements`;
```

**Kết quả:** Tất cả 75 tests tự động gọi URL mới, không cần sửa gì thêm!

**Nếu chỉ đổi 1 endpoint cụ thể:**

```typescript
// src/constants/api.constants.ts

REFINEMENT: {
    // TRƯỚC
    START: buildEndpoint(REFINEMENT_BASE, '/start'),

    // SAU - chỉ đổi endpoint này
    START: buildEndpoint(BASE_API_URL, '/api/v2/refinements/start'),
}
```

---

### 🔧 Tình huống 3: Backend thêm Endpoint mới

**Ví dụ:** Backend thêm API mới `POST /refinements/{sessionId}/export`

**Files cần sửa:** 2 files

#### Bước 1: Thêm vào Constants

```typescript
// src/constants/api.constants.ts

REFINEMENT: {
    START: buildEndpoint(REFINEMENT_BASE, '/start'),
    // ... existing endpoints ...

    // ← THÊM MỚI
    EXPORT: (sessionId: string) => buildEndpoint(REFINEMENT_BASE, `/${sessionId}/export`),
}
```

#### Bước 2: Thêm vào Service

```typescript
// src/refinement/refinement.service.ts

/**
 * Export session data (NEW)
 */
export async function exportSession(
    request: APIRequestContext,
    sessionId: string,
    accessToken: string,
    testName?: string
): Promise<{ status: number; body: unknown }> {
    const url = API_ENDPOINTS.REFINEMENT.EXPORT(sessionId);

    const response = await request.post(url, {
        headers: getAuthHeaders(accessToken),
    });

    logRequest(testName || 'Export session', 'POST', url, { sessionId }, response.status(), HttpStatus.OK);

    return { status: response.status(), body: await response.json() };
}
```

**Giờ có thể dùng trong test:**

```typescript
// tests/api/.../P0-export.spec.ts
const result = await RefinementService.exportSession(request, sessionId, accessToken, testName);
expect(result.status).toBe(200);
```

---

### 🔧 Tình huống 4: Backend đổi Request/Response format

**Ví dụ:** API `/respond` giờ yêu cầu thêm field `deviceId`

**Files cần sửa:** 2 files (Types + Service)

#### Bước 1: Cập nhật Types (nếu có)

```typescript
// src/refinement/refinement.types.ts

// TRƯỚC
export interface SubmitResponsePayload {
    response: string;
}

// SAU
export interface SubmitResponsePayload {
    response: string;
    deviceId: string; // ← THÊM MỚI
}
```

#### Bước 2: Cập nhật Service

```typescript
// src/refinement/refinement.service.ts

export async function submitResponse(
    request: APIRequestContext,
    sessionId: string,
    accessToken: string,
    answer: string,
    testName?: string
): Promise<SubmitResponseResult> {
    const url = API_ENDPOINTS.REFINEMENT.RESPOND(sessionId);

    // TRƯỚC
    const payload = { response: answer };

    // SAU
    const payload = {
        response: answer,
        deviceId: 'test-device-001', // ← THÊM MỚI
    };

    const response = await request.post(url, {
        data: payload,
        headers: getAuthHeaders(accessToken),
    });

    // ... rest of code
}
```

**Không cần sửa:** Tất cả test files - chúng gọi qua Service nên tự động có field mới!

---

### 🔧 Tình huống 5: Thêm tính năng mới (Module mới)

**Ví dụ:** Thêm module "Payment" để test tính năng thanh toán

**Files cần tạo:** 4 files mới

```
src/payment/                    # Tạo folder mới
├── payment.types.ts           # 1. Mô tả data
├── payment.factory.ts         # 2. Tạo test data
├── payment.service.ts         # 3. Gọi API
└── index.ts                   # 4. Export ra ngoài
```

#### File 1: `payment.types.ts`

```typescript
// src/payment/payment.types.ts
export interface PaymentPayload {
    amount: number;
    currency: 'VND' | 'USD';
    method: 'momo' | 'credit_card';
}

export interface PaymentResponse {
    transactionId: string;
    status: 'pending' | 'success' | 'failed';
}
```

#### File 2: `payment.factory.ts`

```typescript
// src/payment/payment.factory.ts
import { faker } from '@faker-js/faker';
import { PaymentPayload } from './payment.types';

export function createPaymentPayload(overrides: Partial<PaymentPayload> = {}): PaymentPayload {
    return {
        amount: faker.number.int({ min: 10000, max: 1000000 }),
        currency: 'VND',
        method: 'momo',
        ...overrides,
    };
}
```

#### File 3: `payment.service.ts`

```typescript
// src/payment/payment.service.ts
import { APIRequestContext } from '@playwright/test';
import { API_ENDPOINTS } from '@src/constants/api.constants';
import { PaymentPayload } from './payment.types';
import { createPaymentPayload } from './payment.factory';
import { TestLogger } from '@src/utils/test-logger';

const logger = TestLogger.getInstance();

export async function createPayment(
    request: APIRequestContext,
    accessToken: string,
    overrides?: Partial<PaymentPayload>,
    testName?: string
) {
    const payload = createPaymentPayload(overrides);
    const url = API_ENDPOINTS.PAYMENT.CREATE;

    logger.request({ method: 'POST', url, payload, expectedStatus: 201, actualStatus: 0, isPass: false });

    const response = await request.post(url, {
        data: payload,
        headers: { Authorization: `Bearer ${accessToken}` },
    });

    return { response, payload };
}
```

#### File 4: `index.ts`

```typescript
// src/payment/index.ts
export * from './payment.types';
export * from './payment.factory';
export * as PaymentService from './payment.service';
```

#### Đừng quên: Thêm endpoints vào Constants

```typescript
// src/constants/api.constants.ts
export const API_ENDPOINTS = {
    // ... existing

    PAYMENT: {
        CREATE: buildEndpoint(BASE_API_URL, '/payments'),
        GET: (id: string) => buildEndpoint(BASE_API_URL, `/payments/${id}`),
    },
};
```

---

### 🔧 Tình huống 6: Sửa logic trong Service (thêm retry, logging, etc.)

**Ví dụ:** Thêm retry 3 lần khi API trả về lỗi 429 (rate limit)

**File cần sửa:** `src/refinement/refinement.service.ts` (chỉ 1 file!)

```typescript
// src/refinement/refinement.service.ts

export async function startSession(
    request: APIRequestContext,
    accessToken: string,
    testName?: string
): Promise<StartSessionResponse> {
    const url = API_ENDPOINTS.REFINEMENT.START;

    // THÊM: Retry logic
    let response;
    let attempts = 0;
    const maxRetries = 3;

    while (attempts < maxRetries) {
        attempts++;
        response = await request.post(url, {
            headers: getAuthHeaders(accessToken),
        });

        // Nếu không bị rate limit, thoát loop
        if (response.status() !== 429) break;

        // Bị rate limit, đợi 2 giây rồi thử lại
        console.log(`⚠️ Rate limited, retry ${attempts}/${maxRetries}...`);
        await new Promise((r) => setTimeout(r, 2000));
    }

    logRequest(testName || 'Start session', 'POST', url, {}, response.status(), HttpStatus.CREATED);

    return response.json();
}
```

**Không cần sửa:** Tests - tất cả tự động có retry logic!

---

## Bảng tóm tắt: Sửa gì ở đâu?

| Tình huống                   | File(s) cần sửa                     | Ví dụ file          |
| ---------------------------- | ----------------------------------- | ------------------- |
| Đổi Base URL                 | `.env` hoặc `env-config.ts`         | 1 file              |
| Đổi 1 endpoint               | `api.constants.ts`                  | 1 file              |
| Thêm endpoint mới            | `api.constants.ts` + `*.service.ts` | 2 files             |
| Đổi request/response format  | `*.types.ts` + `*.service.ts`       | 2 files             |
| Thêm module mới              | Tạo folder mới với 4 files          | 4 files + constants |
| Sửa logic (retry, log, etc.) | `*.service.ts`                      | 1 file              |

---

## Nội dung chi tiết từng thư mục trong `src/`

### 📁 `src/` - Source Utilities

Chứa tất cả code hỗ trợ cho tests. **Tests KHÔNG được viết trong này**.

#### `src/auth/` - Module Authentication

```
src/auth/
├── auth.types.ts           # Type definitions (SignupPayload, LoginPayload, etc.)
├── login/
│   ├── login.factory.ts    # Tạo data login (faker-based)
│   └── login.service.ts    # API calls: loginWithValidCredentials(), etc.
└── signup/
    ├── signup.factory.ts   # Tạo data signup (faker-based)
    └── signup.service.ts   # API calls: signupWithValidData(), etc.
```

**Nhiệm vụ:** Quản lý authentication (signup, login, logout, token refresh).

#### `src/refinement/` - Module Refinement

```
src/refinement/
├── refinement.types.ts     # Types: SessionResponse, QuestionFlow, etc.
├── refinement.service.ts   # API operations: startSession(), respond(), etc.
├── test-data.ts            # Test data constants (Q1-Q7 answers)
└── index.ts                # Re-exports
```

**Nhiệm vụ:** Quản lý AI Conversation flow (7 câu hỏi, skip, edit, resume, confirm).

#### `src/config/` - Configuration

```
src/config/
└── api.config.ts           # API configuration (timeout, headers)
```

**Nhiệm vụ:** Cấu hình HTTP client cho API requests.

#### `src/constants/` - Constants

```
src/constants/
├── api.constants.ts        # Tất cả API endpoints (QUAN TRỌNG!)
└── http-status.ts          # HTTP status codes (200, 201, 400, etc.)
```

**Nhiệm vụ:** Centralize tất cả constants. **KHÔNG hardcode URLs trong tests**.

#### `src/factories/` - Data Factories

```
src/factories/
├── user.factory.ts              # User data generation
├── contextual-flow.factory.ts   # Q1-Q7 contextual answers
└── index.ts                     # Re-exports
```

**Nhiệm vụ:** Tạo test data unique mỗi lần chạy (faker + timestamp) để đảm bảo parallel safety.

#### `src/fixtures/` - Playwright Fixtures

```
src/fixtures/
├── custom.fixtures.ts      # Base fixtures (testUser, etc.)
├── refinement.fixture.ts   # Refinement-specific fixtures (với auto-cleanup)
└── index.ts                # Merged fixtures export
```

**Nhiệm vụ:** Playwright fixtures với auto-setup và auto-cleanup resources.

#### `src/utils/` - Utilities

```
src/utils/
├── env-config.ts           # Environment configuration (stg/rel/prod)
└── test-logger.ts          # Test logging với PASS/FAIL status
```

**Nhiệm vụ:** Tiện ích chung: logging, environment switching.

---

## 📚 Danh sách Functions có thể Reuse

> **Mục đích:** Giúp team member tra cứu nhanh các function có sẵn để reuse, không cần viết lại.

---

### 🔧 Service Functions (`refinement.service.ts`)

**File:** `src/refinement/refinement.service.ts`

**Import:**

```typescript
import { RefinementService } from '@src/refinement';
// hoặc
import * as RefinementService from '@src/refinement/refinement.service';
```

#### Session Management (Quản lý session)

| Function           | Mục đích              | Khi nào dùng                  |
| ------------------ | --------------------- | ----------------------------- |
| `startSession()`   | Tạo session mới       | Bắt đầu flow Q1-Q7            |
| `getSession()`     | Lấy thông tin session | Kiểm tra trạng thái session   |
| `resumeSession()`  | Resume session cũ     | Test resume sau khi thoát app |
| `abandonSession()` | Hủy session           | Cleanup sau test              |
| `deleteSession()`  | Xóa session vĩnh viễn | Test hard delete              |

**Ví dụ sử dụng:**

```typescript
// Tạo session mới
const session = await RefinementService.startSession(request, accessToken, 'Test tạo session');
console.log(session.sessionId); // "abc-123"

// Lấy thông tin session
const { status, body } = await RefinementService.getSession(request, sessionId, accessToken);
console.log(body.currentQuestion); // 1

// Resume session cũ
const resumed = await RefinementService.resumeSession(request, sessionId, accessToken);

// Cleanup
await RefinementService.abandonSession(request, sessionId, accessToken);
```

---

#### Response Submission (Gửi câu trả lời)

| Function                          | Mục đích                    | Khi nào dùng                      |
| --------------------------------- | --------------------------- | --------------------------------- |
| `submitResponse()`                | Gửi câu trả lời Q1-Q7       | Test happy path                   |
| `submitResponseRaw()`             | Gửi và lấy raw response     | Test error cases (400, 401, etc.) |
| `submitResponseForSecurityTest()` | Gửi payload độc hại         | Test XSS, SQL injection           |
| `answerQuestions()`               | Trả lời nhiều câu liên tiếp | Nhanh chóng đến Qn                |
| `completeAllQuestions()`          | Trả lời hết 7 câu           | Test confirm concept              |

**Ví dụ sử dụng:**

```typescript
// Trả lời 1 câu
const result = await RefinementService.submitResponse(
    request,
    sessionId,
    accessToken,
    'Tôi muốn tạo app học tiếng Anh',
    'Test Q1'
);
console.log(result.currentQuestion); // 2

// Test lỗi (expect 400)
const error = await RefinementService.submitResponseRaw(
    request,
    sessionId,
    accessToken,
    '', // empty response
    'Test empty',
    400 // expected status
);
console.log(error.status); // 400

// Trả lời từ Q1 đến Q5 nhanh
const answers = ['Answer 1', 'Answer 2', 'Answer 3', 'Answer 4', 'Answer 5'];
await RefinementService.answerQuestions(request, sessionId, accessToken, answers, 1, 5, 'Bulk answers');

// Hoàn thành hết 7 câu
await RefinementService.completeAllQuestions(request, sessionId, accessToken, allAnswers, 'Complete flow');
```

---

#### Skip & Edit Flow

| Function          | Mục đích                    | Khi nào dùng            |
| ----------------- | --------------------------- | ----------------------- |
| `skipQuestion()`  | Bỏ qua câu hỏi hiện tại     | Test skip flow          |
| `editQuestion()`  | Sửa câu trả lời đã submit   | Test edit flow          |
| `confirmImpact()` | Xác nhận ảnh hưởng sau edit | Sau khi edit thành công |

**Ví dụ sử dụng:**

```typescript
// Skip câu hỏi hiện tại
const skipResult = await RefinementService.skipQuestion(request, sessionId, accessToken, 'Test skip Q2');
console.log(skipResult.body.skippedQuestions); // [2]

// Edit câu trả lời Q1
const editResult = await RefinementService.editQuestion(
    request,
    sessionId,
    accessToken,
    1, // question number
    { response: 'Câu trả lời mới cho Q1' },
    'Test edit Q1'
);

// Confirm impact sau edit
const confirmResult = await RefinementService.confirmImpact(
    request,
    sessionId,
    accessToken,
    1, // question number
    { confirmed: true },
    'Confirm edit Q1'
);
```

---

#### History & Concept

| Function           | Mục đích                   | Khi nào dùng                |
| ------------------ | -------------------------- | --------------------------- |
| `getHistory()`     | Lấy lịch sử Q&A            | Verify các câu trả lời      |
| `getConcept()`     | Lấy concept data           | Verify AI-generated concept |
| `updateConcept()`  | Cập nhật concept           | Test manual edit concept    |
| `confirmConcept()` | Xác nhận concept cuối cùng | Test confirm flow           |

**Ví dụ sử dụng:**

```typescript
// Lấy lịch sử
const history = await RefinementService.getHistory(request, sessionId, accessToken, 'Get history');
console.log(history.responses.length); // 7

// Lấy concept
const concept = await RefinementService.getConcept(request, sessionId, accessToken, 'Get concept');
console.log(concept.title); // "Video Editing Course"

// Confirm concept
const confirmed = await RefinementService.confirmConcept(request, sessionId, accessToken, 'Confirm');
```

---

#### Analytics & Health

| Function                    | Mục đích           | Khi nào dùng              |
| --------------------------- | ------------------ | ------------------------- |
| `getHealth()`               | Health check API   | Verify API đang hoạt động |
| `getAbandonmentAnalytics()` | Thống kê abandon   | Test analytics            |
| `getVaguenessAnalytics()`   | Thống kê vagueness | Test analytics            |

---

### 🏭 Factory Functions (`contextual-flow.factory.ts`)

**File:** `src/factories/contextual-flow.factory.ts`

**Import:**

```typescript
import {
    createContextualAnswers,
    createVagueAnswers,
    createSecurityPayloads,
    // ...
} from '@src/factories/contextual-flow.factory';
```

#### Tạo Test Data cho Q1-Q7

| Function                    | Mục đích                        | Khi nào dùng                 |
| --------------------------- | ------------------------------- | ---------------------------- |
| `createContextualAnswers()` | Tạo bộ 7 câu trả lời hoàn chỉnh | Test happy path flow         |
| `getAnswersArray()`         | Convert thành array             | Dùng với `answerQuestions()` |
| `getAnswersRange()`         | Lấy 1 phần answers              | Trả lời từ Qn đến Qm         |

**Ví dụ sử dụng:**

```typescript
// Tạo bộ 7 câu trả lời
const answers = createContextualAnswers();
console.log(answers.q1_content); // "I want to create a comprehensive video editing course..."
console.log(answers.q2_audience); // "My target audience is specifically freelance video editors..."

// Override 1 câu trả lời
const customAnswers = createContextualAnswers({
    q1_content: 'App học tiếng Nhật cho người Việt',
});

// Convert thành array để dùng với answerQuestions()
const answersArray = getAnswersArray(answers);
// → ['Answer Q1', 'Answer Q2', ..., 'Answer Q7']

// Lấy Q1-Q3
const firstThree = getAnswersRange(answers, 1, 3);
// → ['Answer Q1', 'Answer Q2', 'Answer Q3']
```

---

#### Tạo Vague Answers (Test Clarification)

| Function               | Mục đích                | Khi nào dùng          |
| ---------------------- | ----------------------- | --------------------- |
| `createVagueAnswer()`  | Tạo 1 câu trả lời mơ hồ | Test AI clarification |
| `createVagueAnswers()` | Tạo nhiều câu mơ hồ     | Test nhiều scenarios  |

**Ví dụ sử dụng:**

```typescript
// Tạo câu trả lời mơ hồ để trigger AI clarification
const vague = createVagueAnswer();
// → "I want to make a course about stuff"

const result = await RefinementService.submitResponse(request, sessionId, accessToken, vague, 'Test vague');
// AI sẽ hỏi lại để clarify
```

---

#### Tạo Pricing Data

| Function                        | Mục đích                  | Khi nào dùng          |
| ------------------------------- | ------------------------- | --------------------- |
| `createValidPricing()`          | Pricing hợp lệ ($99-$499) | Test happy path Q7    |
| `createLowPricing()`            | Pricing quá thấp (<$99)   | Test AI clarification |
| `createHighPricing()`           | Pricing cao ($40K-$50K)   | Test boundary         |
| `create4To6WeekCoursePricing()` | Pricing theo format       | Test pricing logic    |
| `createMembershipPricing()`     | Pricing membership        | Test monthly pricing  |
| `createWorkshopPricing()`       | Pricing workshop          | Test workshop pricing |

**Ví dụ sử dụng:**

```typescript
// Pricing hợp lệ
const validPrice = createValidPricing();
// → "$297 early bird pricing, $397 regular price. Includes lifetime access..."

// Pricing quá thấp (trigger clarification)
const lowPrice = createLowPricing();
// → "$30 early bird pricing, $50 regular price..."

// Pricing theo course format
const coursePrice = create4To6WeekCoursePricing('intermediate');
// → "$99 early bird, $149 regular for this intermediate 4-6 week course..."
```

---

#### Tạo Security Payloads

| Function                   | Mục đích                  | Khi nào dùng         |
| -------------------------- | ------------------------- | -------------------- |
| `createSecurityPayloads()` | Tạo tất cả attack vectors | Test security        |
| `getSecurityPayload()`     | Lấy 1 loại payload        | Test 1 attack cụ thể |

**Ví dụ sử dụng:**

```typescript
// Lấy tất cả security payloads
const payloads = createSecurityPayloads();
// → [{ type: 'xss', payload: '<script>...' }, { type: 'sql_injection', ... }]

// Lấy payload cụ thể
const xssPayload = getSecurityPayload('xss');
// → '<script>alert("xss")</script>'

// Test security
const result = await RefinementService.submitResponseForSecurityTest(
    request,
    sessionId,
    accessToken,
    xssPayload,
    'Test XSS'
);
expect(result.status).toBe(400); // Should be blocked
```

---

#### Tạo Edge Case Data

| Function                       | Mục đích                 | Khi nào dùng        |
| ------------------------------ | ------------------------ | ------------------- |
| `createLongValidInput()`       | Input dài nhưng hợp lệ   | Test performance    |
| `createExcessiveLengthInput()` | Input >5000 chars        | Test validation     |
| `createInvalidSessionIds()`    | Session IDs không hợp lệ | Test error handling |

**Ví dụ sử dụng:**

```typescript
// Input dài (~1200 chars)
const longInput = createLongValidInput(1200);

// Input quá dài (>5000 chars) → expect reject
const tooLong = createExcessiveLengthInput();
const result = await RefinementService.submitResponseRaw(
    request,
    sessionId,
    accessToken,
    tooLong,
    'Test too long',
    400
);

// Session IDs không hợp lệ
const invalidIds = createInvalidSessionIds();
// → ['nonexistent_session_id', 'invalid!@#$%', ...]
```

---

### 📊 Bảng tra cứu nhanh: Function nào cho tình huống nào?

| Tình huống test                       | Function cần dùng                                              |
| ------------------------------------- | -------------------------------------------------------------- |
| **Happy path flow Q1-Q7**             | `createContextualAnswers()` + `submitResponse()`               |
| **Test validation (empty, too long)** | `submitResponseRaw()` với expected status                      |
| **Test AI clarification**             | `createVagueAnswer()` + `submitResponse()`                     |
| **Test security (XSS, SQL)**          | `createSecurityPayloads()` + `submitResponseForSecurityTest()` |
| **Test skip flow**                    | `skipQuestion()`                                               |
| **Test edit flow**                    | `editQuestion()` + `confirmImpact()`                           |
| **Test resume flow**                  | `resumeSession()`                                              |
| **Test pricing logic**                | `createValidPricing()`, `createLowPricing()`, etc.             |
| **Test error handling**               | `createInvalidSessionIds()` + `getSession()`                   |
| **Cleanup sau test**                  | `abandonSession()`                                             |

---

### 💡 Tips khi Reuse Functions

1. **Luôn truyền `testName`** - giúp log rõ ràng khi debug

    ```typescript
    await RefinementService.startSession(request, token, '[P0][TC-001] Test start session');
    ```

2. **Dùng `*Raw()` functions khi test lỗi** - trả về status code thay vì throw error

    ```typescript
    const { status, body } = await RefinementService.submitResponseRaw(...);
    expect(status).toBe(400);
    ```

3. **Dùng Factory với overrides** - không cần tạo data từ đầu

    ```typescript
    const answers = createContextualAnswers({ q1_content: 'Custom answer' });
    ```

4. **Fixture tự động cleanup** - không cần gọi `abandonSession()` thủ công nếu dùng fixture
    ```typescript
    test('...', async ({ session }) => {
        // session tự động được tạo và cleanup
    });
    ```

---

### 📁 `tests/` - Test Specifications

Chứa tất cả test cases. Tách biệt API tests và E2E tests.

#### `tests/api/` - API Tests

```
tests/api/
├── auth/                   # Authentication tests
│   ├── P0-login.spec.ts
│   ├── P1-login.spec.ts
│   ├── P2-login.spec.ts
│   └── signup-with-3-fields.spec.ts
│
└── conversation/           # AI Conversation tests
    ├── phase1/             # Phase 1 implementation
    │   ├── story-02.1.1-ai-conversation-engine/
    │   │   ├── P0-conversation-flow.spec.ts
    │   │   ├── P0-validation.spec.ts
    │   │   ├── P0-security.spec.ts
    │   │   ├── P0-atomic-save.spec.ts
    │   │   ├── P1-edit-flow.spec.ts
    │   │   ├── P1-skip-flow.spec.ts
    │   │   ├── P2-error-handling.spec.ts
    │   │   └── P3-performance.spec.ts
    │   │
    │   ├── story-02.1.2-contextual-question-flow/
    │   ├── story-02.1.3-ai-response-validation/
    │   ├── story-02.1.5-output-confirmation-step/
    │   ├── story-02.3.1-auto-save-engine/
    │   └── story-02.3.2-session-expiry-logic/
    │
    └── phase2/             # Phase 2 (future)
```

**Naming Convention:**

- `P0` = Critical path (phải pass)
- `P1` = Important (nên pass)
- `P2` = Nice to have
- `P3` = Performance tests

**Chạy tests:**

```bash
# Tất cả API tests
npx playwright test --project=api

# Theo priority
npx playwright test --project=api --grep "P0"

# Theo story
npx playwright test tests/api/conversation/phase1/story-02.1.1-*
```

#### `tests/e2e/` - E2E Tests

```
tests/e2e/
└── example.spec.ts         # E2E tests với browser
```

**Nhiệm vụ:** Browser-based tests (Chrome, Firefox, Safari).

---

### 📁 `docs/` - Documentation

```
docs/
├── api/                    # API documentation
├── sprint2/
│   ├── squad-coca/         # Squad Coca (Login/Signup)
│   │   ├── login/story/
│   │   └── signup/story/
│   └── squad-idea/         # Squad Idea (AI Conversation)
│       └── story/
│           ├── story-02.1.1/   # Bug logs, test reports
│           ├── story-02.1.2/
│           └── ...
├── sprint3/
│   └── squad-idea/
└── templates/
    ├── log-bug-api-template.md
    └── test-report-api-template.md
```

**Nhiệm vụ:** Lưu trữ tài liệu: stories, bug logs, test reports.

---

### 📁 Thư mục khác

#### `.husky/` - Git Hooks

Pre-commit hooks tự động:

- ESLint fix
- Prettier format

#### `.github/workflows/` - CI/CD

GitHub Actions workflows cho automated testing.

#### `_bmad/` - BMAD Method

Framework hỗ trợ AI agents trong development workflow.

---

## Patterns quan trọng

### 1. Service Pattern

**❌ KHÔNG làm:**

```typescript
// Trong test file
await request.post('https://api.example.com/auth/signup', { data });
```

**✅ LÀM:**

```typescript
// Trong test file
import * as SignupService from '@src/auth/signup/signup.service';
const { response } = await SignupService.signupWithValidData(request);
```

### 2. Factory Pattern

**❌ KHÔNG làm:**

```typescript
const payload = { email: 'test@test.com', password: 'Test123!' };
```

**✅ LÀM:**

```typescript
import { createSignupPayload } from '@src/auth/signup/signup.factory';
const payload = createSignupPayload(); // Unique mỗi lần
```

### 3. Endpoint Constants

**❌ KHÔNG làm:**

```typescript
await request.post('/refinements/start');
```

**✅ LÀM:**

```typescript
import { API_ENDPOINTS } from '@src/constants/api.constants';
await request.post(API_ENDPOINTS.REFINEMENT.START);
```

---

## Commands thường dùng

| Command               | Mô tả                    |
| --------------------- | ------------------------ |
| `npm run test:e2e`    | Chạy tất cả tests        |
| `npm run test:ui`     | Mở Playwright UI         |
| `npm run test:headed` | Chạy với browser visible |
| `npm run lint`        | Kiểm tra code style      |
| `npm run lint:fix`    | Tự động fix code style   |
| `npm run format`      | Format code với Prettier |

---

## Environment Setup

### File `.env`

```env
TEST_ENV=stg                              # stg | rel | prod
API_URL=https://sproux-api.beincom.app    # Optional override
API_TIMEOUT=30000
LOG_MODE=local                            # local | prod
```

### Environment URLs

| Environment   | URL                            |
| ------------- | ------------------------------ |
| stg (default) | https://sproux-api.beincom.app |
| rel           | https://sproux-api.beincom.biz |
| prod          | https://api.sproux.com         |

---

## Ví dụ thực tế: Các tình huống người mới thường gặp

> **Lưu ý cho người mới:** Phần này sử dụng các ví dụ từ code thật trong project. Bạn có thể mở các file được đề cập để xem chi tiết.

---

### 📌 Tình huống 1: "Mình muốn chạy test lần đầu"

**Bối cảnh:** Bạn vừa clone project về, cài đặt xong dependencies, giờ muốn chạy test thử.

#### Bước 1: Kiểm tra đã cài dependencies chưa

```bash
# Mở Terminal trong VS Code (Ctrl + `)
npm install
```

Nếu thấy thông báo "up to date" nghĩa là đã cài xong.

#### Bước 2: Tạo file .env

```bash
# Copy file mẫu
cp .env.example .env
```

Hoặc tạo file `.env` ở thư mục gốc với nội dung:

```env
TEST_ENV=stg
LOG_MODE=local
```

#### Bước 3: Chạy test

```bash
# Chạy tất cả test API
npx playwright test --project=api

# Nếu muốn xem giao diện đẹp hơn
npm run test:ui
```

#### Kết quả mong đợi:

```
Running 75 tests using 1 worker

  ✓ [P0][TC-001] Start session successfully (2.5s)
  ✓ [P0][TC-005] Empty response returns 400 (1.2s)
  ...

  75 passed (2m 30s)
```

**❓ Nếu lỗi "Cannot find module":** Chạy `npm install` lại.

**❓ Nếu lỗi "401 Unauthorized":** Kiểm tra file `.env` có đúng `TEST_ENV=stg` không.

---

### 📌 Tình huống 2: "Mình muốn chạy chỉ 1 test cụ thể"

**Bối cảnh:** Bạn đang fix bug hoặc viết test mới, chỉ muốn chạy test đó thôi, không chạy hết 75 tests.

#### Cách 1: Chạy theo tên file

```bash
# Chạy 1 file cụ thể
npx playwright test tests/api/conversation/phase1/story-02.1.1-ai-conversation-engine/P0-validation.spec.ts
```

#### Cách 2: Chạy theo tên test (grep)

```bash
# Chạy test có chứa chữ "Empty response"
npx playwright test --grep "Empty response"

# Chạy tất cả test P0
npx playwright test --grep "P0"

# Chạy tất cả test của story 02.1.1
npx playwright test --grep "02.1.1"
```

#### Cách 3: Dùng .only trong code (nhanh nhất khi dev)

Mở file test, thêm `.only` vào test muốn chạy:

```typescript
// TRƯỚC - chạy tất cả tests trong file
test('[P0] Empty response returns 400', async ({ request, session }) => {
    // ...
});

// SAU - chỉ chạy test này
test.only('[P0] Empty response returns 400', async ({ request, session }) => {
    // ...
});
```

Rồi chạy:

```bash
npx playwright test tests/api/.../P0-validation.spec.ts
```

**⚠️ QUAN TRỌNG:** Nhớ xóa `.only` trước khi commit, không thì CI chỉ chạy 1 test!

---

### 📌 Tình huống 3: "Test bị fail, làm sao debug?"

**Bối cảnh:** Chạy test thấy fail, không biết sai ở đâu.

#### Bước 1: Đọc output trong terminal

Khi test fail, Playwright sẽ show:

```
  ✗ [P0][TC-005] Empty response returns 400 (1.2s)

    Error: expect(received).toBe(expected)

    Expected: 400
    Received: 201

      at tests/api/.../P0-validation.spec.ts:86:20
```

**Giải thích:**

- `Expected: 400` = Test mong đợi API trả về status 400
- `Received: 201` = Nhưng API thực tế trả về 201
- `P0-validation.spec.ts:86:20` = Lỗi ở file này, dòng 86, cột 20

#### Bước 2: Xem log chi tiết

Test trong project có log rõ ràng. Tìm phần:

```
🧪 [P0][TC-005] Empty response returns 400 RESPONSE_EMPTY
   [POST] https://sproux-api.beincom.app/refinements/abc123/respond
   📋 {"response":""}
   📥 Expected: 400 | Actual: 201 → ❌ FAIL
```

**Giải thích:**

- `[POST]` = Gọi API method POST
- URL = Endpoint được gọi
- `📋` = Payload gửi đi
- `Expected: 400 | Actual: 201` = Mong đợi vs thực tế

#### Bước 3: Chạy với UI mode để debug từng bước

```bash
npm run test:ui
```

Trong UI:

1. Click vào test bị fail
2. Xem từng step một
3. Click vào step để xem request/response chi tiết

#### Bước 4: Thêm console.log (cách truyền thống)

```typescript
test('[P0] Empty response returns 400', async ({ request, session }) => {
    console.log('Session:', session);  // Xem session có gì

    const response = await RefinementService.submitResponseRaw(...);

    console.log('Response status:', response.status);  // Xem status
    console.log('Response body:', response.body);      // Xem body

    expect(response.status).toBe(400);
});
```

---

### 📌 Tình huống 4: "Mình muốn thêm test case mới"

**Bối cảnh:** Được giao viết thêm test case cho feature đã có sẵn.

#### Ví dụ thực tế: Thêm test kiểm tra response quá ngắn

**File cần sửa:** `tests/api/conversation/phase1/story-02.1.1-ai-conversation-engine/P0-validation.spec.ts`

#### Bước 1: Mở file test hiện có

```typescript
// Đây là file P0-validation.spec.ts có sẵn

import { test, expect, RefinementService } from '@src/refinement';
import { HttpStatus } from '@src/constants/http-status';

test.describe('P0 - Validation Tests', () => {
    // Các tests có sẵn...
    // 👇 THÊM TEST MỚI Ở ĐÂY
});
```

#### Bước 2: Copy 1 test có sẵn làm template

```typescript
// Copy test này làm mẫu:
test('[P0][TC-005] Empty response returns 400', async ({ request, session }) => {
    const testName = '[P0][TC-005] Empty response returns 400';

    // Gửi response rỗng
    const response = await RefinementService.submitResponseRaw(
        request,
        session.sessionId,
        session.accessToken,
        '', // input rỗng
        testName,
        HttpStatus.BAD_REQUEST
    );

    expect(response.status).toBe(HttpStatus.BAD_REQUEST);
});
```

#### Bước 3: Sửa thành test mới

```typescript
// Test mới: kiểm tra response quá ngắn (dưới 10 ký tự)
test('[P0][TC-007] Response too short returns 400', async ({ request, session }) => {
    const testName = '[P0][TC-007] Response too short returns 400';

    // Gửi response quá ngắn
    const response = await RefinementService.submitResponseRaw(
        request,
        session.sessionId,
        session.accessToken,
        'abc', // chỉ 3 ký tự
        testName,
        HttpStatus.BAD_REQUEST
    );

    expect(response.status).toBe(HttpStatus.BAD_REQUEST);
});
```

#### Bước 4: Chạy test mới

```bash
npx playwright test --grep "TC-007"
```

**💡 Mẹo:**

- Copy test có sẵn → sửa lại → nhanh hơn viết từ đầu
- Giữ nguyên format `[P0][TC-XXX]` để dễ tracking
- Test ID (TC-XXX) nên unique trong file

---

### 📌 Tình huống 5: "Mình cần tìm code test có sẵn để tham khảo"

**Bối cảnh:** Không biết viết test như nào, muốn xem code mẫu.

#### Nơi tìm code mẫu:

| Loại test                        | File mẫu                                     |
| -------------------------------- | -------------------------------------------- |
| Test validation (kiểm tra input) | `tests/api/.../P0-validation.spec.ts`        |
| Test flow đầy đủ (happy path)    | `tests/api/.../P0-conversation-flow.spec.ts` |
| Test bảo mật (security)          | `tests/api/.../P0-security.spec.ts`          |
| Test lỗi (error handling)        | `tests/api/.../P2-error-handling.spec.ts`    |
| Test hiệu năng (performance)     | `tests/api/.../P3-performance.spec.ts`       |

#### Ví dụ: Xem test validation thật

Mở file `tests/api/conversation/phase1/story-02.1.1-ai-conversation-engine/P0-validation.spec.ts`:

```typescript
// Đây là code thật từ project

test('[P0][TC-005] Empty response returns 400 RESPONSE_EMPTY', async ({ request, session }) => {
    const testName = '[P0][TC-005] Empty response returns 400 RESPONSE_EMPTY';
    const logger = TestLogger.getInstance();

    // GIVEN: Có session đang ở Q1
    logger.log('[GIVEN] Active session at Q1');
    logger.log(`  Session ID: ${session.sessionId}`);
    expect(session.currentQuestion).toBe(1);

    // WHEN: Gửi response rỗng
    logger.log('[WHEN] Submit empty responses');
    const emptyInputs = ['', '   ', '\n\n', '\t'];

    let hasError = false;
    for (const input of emptyInputs) {
        const response = await RefinementService.submitResponseRaw(
            request,
            session.sessionId,
            session.accessToken,
            input,
            testName,
            HttpStatus.BAD_REQUEST
        );

        if (response.status === HttpStatus.BAD_REQUEST) {
            hasError = true;
            break;
        }
    }

    // THEN: API trả về lỗi 400
    logger.log('[THEN] Verify error response');
    expect(hasError).toBe(true);
});
```

**Giải thích cấu trúc:**

1. `test('[P0][TC-005]...')` - Tên test với priority và test ID
2. `{ request, session }` - Fixtures tự động được inject
3. `GIVEN/WHEN/THEN` - Pattern mô tả test case
4. `RefinementService.submitResponseRaw()` - Gọi API qua service (không gọi trực tiếp)
5. `expect()` - Kiểm tra kết quả

---

### 📌 Tình huống 6: "Backend đổi API, phải sửa ở đâu?"

**Bối cảnh:** Dev thông báo đã đổi endpoint hoặc response format.

#### Trường hợp 1: Đổi URL endpoint

**Ví dụ:** Đổi từ `/refinements/start` → `/api/v2/refinements/start`

**Chỉ sửa 1 file:**

```typescript
// src/constants/api.constants.ts

// TRƯỚC
const REFINEMENT_BASE = '/refinements';

// SAU
const REFINEMENT_BASE = '/api/v2/refinements';
```

**Không cần sửa gì thêm!** Tất cả 75 tests tự động dùng URL mới.

#### Trường hợp 2: Đổi tên field trong response

**Ví dụ:** API đổi `sessionId` → `session_id`

**Sửa file types:**

```typescript
// src/refinement/refinement.types.ts

// TRƯỚC
export interface StartSessionResponse {
    sessionId: string;
    currentQuestion: number;
}

// SAU
export interface StartSessionResponse {
    session_id: string; // ← Đổi tên field
    currentQuestion: number;
}
```

**Sửa file service (nếu cần map lại):**

```typescript
// src/refinement/refinement.service.ts

export async function startSession(...): Promise<StartSessionResponse> {
    const response = await request.post(url, ...);
    const data = await response.json();

    // Map field name nếu cần giữ tương thích
    return {
        sessionId: data.session_id,  // Map từ snake_case sang camelCase
        currentQuestion: data.currentQuestion
    };
}
```

#### Trường hợp 3: Thêm field bắt buộc mới

**Ví dụ:** API yêu cầu thêm `deviceId` khi gọi

**Sửa 2 files:**

```typescript
// 1. Thêm vào types
// src/refinement/refinement.types.ts
export interface SubmitPayload {
    response: string;
    deviceId: string;  // ← Thêm field mới
}

// 2. Thêm vào service
// src/refinement/refinement.service.ts
export async function submitResponse(...) {
    const payload = {
        response: answer,
        deviceId: 'test-device-001'  // ← Thêm field mới
    };
    // ...
}
```

**Không cần sửa test files!**

---

### 📌 Tình huống 7: "Test pass ở local nhưng fail ở CI"

**Bối cảnh:** Chạy test trên máy mình thì pass, nhưng CI báo fail.

#### Nguyên nhân thường gặp:

| Nguyên nhân          | Cách fix                                          |
| -------------------- | ------------------------------------------------- |
| Quên commit file mới | `git status` để kiểm tra, rồi `git add .`         |
| File .env khác nhau  | CI dùng env variables, không dùng file .env       |
| Timeout quá ngắn     | Tăng timeout trong test hoặc playwright.config.ts |
| Race condition       | Thêm `await` hoặc dùng `waitFor`                  |

#### Kiểm tra CI logs:

1. Vào GitHub → tab "Actions"
2. Click vào workflow đang fail
3. Xem logs để tìm test nào fail
4. So sánh với output khi chạy local

#### Debug bằng cách chạy giống CI:

```bash
# Chạy với env giống CI
TEST_ENV=stg LOG_MODE=prod npx playwright test --project=api

# Chạy nhiều lần để detect flaky test
npx playwright test --repeat-each=3
```

---

### 📌 Tình huống 8: "Muốn xem API trả về gì thật"

**Bối cảnh:** Không biết API response có format như nào để viết expect.

#### Cách 1: Thêm console.log trong test

```typescript
test('Debug API response', async ({ request, session }) => {
    const response = await RefinementService.submitResponseRaw(
        request,
        session.sessionId,
        session.accessToken,
        'Test answer',
        'Debug test'
    );

    // In ra toàn bộ response
    console.log('Status:', response.status);
    console.log('Body:', JSON.stringify(response.body, null, 2));

    // Tạm thời expect false để test fail và show log
    expect(true).toBe(false);
});
```

#### Cách 2: Dùng Playwright UI

```bash
npm run test:ui
```

Trong UI:

1. Chạy test
2. Click vào network request
3. Xem Response tab

#### Cách 3: Dùng Postman/curl song song

```bash
# Xem response trực tiếp
curl -X POST https://sproux-api.beincom.app/refinements/start \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json"
```

---

## Tổng kết: Khi nào sửa file nào?

### Bảng tra cứu nhanh cho người mới

| Tình huống               | File cần sửa                  | Ví dụ file              |
| ------------------------ | ----------------------------- | ----------------------- |
| Thêm test case mới       | Test file                     | `P0-validation.spec.ts` |
| API đổi URL              | `api.constants.ts`            | 1 file duy nhất         |
| API đổi request/response | `*.types.ts` + `*.service.ts` | `refinement.types.ts`   |
| Đổi môi trường test      | `.env`                        | TEST_ENV=stg/rel/prod   |
| Debug test fail          | Không sửa, chỉ xem log        | Terminal output         |

### Quy tắc vàng cho người mới

1. **Luôn copy test có sẵn** làm template, không viết từ đầu
2. **Không gọi API trực tiếp** - luôn dùng Service functions
3. **Không hardcode URL/data** - luôn dùng constants và factories
4. **Chạy test thường xuyên** - `npx playwright test --grep "tên-test"`
5. **Đọc log khi fail** - tìm `Expected` vs `Actual`

---

## Liên hệ

- **QC Team Lead:** [Contact info]
- **Documentation:** `docs/`
- **Bug Reports:** `docs/sprint{N}/squad-{name}/story/`

---

_Tài liệu này được tạo bởi Winston (Architect Agent) - "Boring technology that works."_
