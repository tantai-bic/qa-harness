---
name: test-quality-checklist
description: Source of Truth cho test quality — 9 rules + 41 checklist items, 100% compliance required. Bao gồm Rule #1 chống "cho có" testing, Rule #2 chỉ test theo tài liệu, Rule #3 tránh pixel positions, Rule #4 UI vs content test, Rule #5 DRY, Rule #6 split P0/P1/P2, Rule #7 type safety, Rule #8 test fails ≠ test sai, Rule #9 service integration. Dùng khi viết/review test code, audit quality, hoặc trước khi mark task complete.
---

# Test Quality Checklist - Source of Truth

**Date:** 2026-01-12 | **Last Updated:** 2026-01-13 (Added Rule #9)
**Status:** 9 Rules | 41 Checklist Items | 100% Compliance Required

---

## 📖 MỤC LỤC - QUICK REFERENCE

### 🎯 9 RULES - Đọc Này Trước (Token-Optimized)

| Rule   | Tên                                                      | Vấn Đề Giải Quyết                                | Khi Nào Dùng                         |
| ------ | -------------------------------------------------------- | ------------------------------------------------ | ------------------------------------ |
| **#1** | [Chống "Cho Có"](#1️⃣-chống-cho-có-testing)               | Test pass dù có bug (check visibility only)      | Mọi test - verify actual behavior    |
| **#2** | [Test Theo Tài Liệu](#2️⃣-chỉ-test-theo-tài-liệu)         | Thêm requirements tự suy (WCAG, Material Design) | Mọi test - chỉ test theo test-design |
| **#3** | [Tránh Pixel Positions](#3️⃣-tránh-pixel-positions)       | Hard-code X/Y breaks on different viewports      | UI tests - check CSS not coordinates |
| **#4** | [UI Test vs Content](#4️⃣-ui-test-vs-content-test)        | UI test check AI content quality                 | UI tests - check render not content  |
| **#5** | [DRY Principle](#5️⃣-không-duplicate-code-dry)            | Duplicate test data across files                 | Mọi test - reuse test-data.ts        |
| **#6** | [Test Organization](#6️⃣-chỉ-test-p0-trong-p0-file)       | Mix P0/P1/P2 trong cùng file                     | Mọi test - đúng priority file        |
| **#7** | [Type Safety](#7️⃣-typescript-type-safety)                | Dùng `any`/`unknown` bypass type checking        | Mọi test - cast to inline interface  |
| **#8** | [Test Fails ≠ Sai](#8️⃣-test-fails-≠-test-sai)            | Change test để pass khi backend sai              | Test fails - apply decision tree     |
| **#9** | [Service Integration](#9️⃣-service-layer-integration-new) | Wrong parameters/payload/method name             | API tests - read signature first     |

### 📋 Quick Checklist (41 items)

**Pre-Implementation (6):** Test-design → Priority → Test data → Service signature → Payload structure
**During Implementation (9):** Single requirement → API-DOC refs → No external specs → Count params → Verify method name
**Verification (5):** Test fails if empty? if "undefined"? if initial state wrong?
**Code Quality (5):** Reuse test-data.ts → No duplicates → Correct file → Type safety
**Service Integration (6):** Signature correct? Method exists? Payload correct? Order correct? Run TypeScript
**Final Review (5):** Catch bugs? Break implementation? No "cho có"? Service calls correct?
**When Fails (5):** Follows test-design? Backend matches? API-DOC documents? Never change test

---

## 🎯 NGUYÊN TẮC VÀNG - TÓM TẮT 30 GIÂY

### Hierarchy of Truth (Source of Truth)

1. 🥇 **Test Design Document** = Requirements (HIGHEST authority)
2. 🥈 **Test Code** = Verification (follows test-design)
3. 🥉 **Backend** = Implementation (can have bugs)
4. 🏅 **API-DOC.md** = Documentation (can be outdated)

### Golden Rules

1. ✅ **Check ACTUAL behavior** (not just visibility)
2. ✅ **Only test what's documented** (test-design + API-DOC line refs)
3. ✅ **Reuse test data** (DRY - from test-data.ts)
4. ✅ **Cast to inline interface** (no `any`/`unknown`)
5. ✅ **Read service signature FIRST** (count params, check types, verify method name)
6. ❌ **If test follows test-design → Test ALWAYS CORRECT** (backend ALWAYS WRONG)
7. ❌ **NEVER change test to pass when backend wrong**

---

## 1️⃣ CHỐNG "CHO CÓ" TESTING

### ❌ Lỗi Thường Gặp

```typescript
// ❌ CHO CÓ: Chỉ check visibility
await expect(page.locator(field)).toBeVisible(); // Pass kể cả field = "undefined"

// ❌ CHO CÓ: Check keyword quá loose
expect(text).toMatch(/creator/i); // Pass với "creator" (1 word, 95% data missing)

// ❌ CHO CÓ: Không verify initial state
await checkbox.click(); // Không verify checkbox bắt đầu unchecked
```

### ✅ Cách Đúng

```typescript
// ✅ Check field có CONTENT (not just visible)
const text = await element.textContent();
expect(text?.trim().length, 'Field should have content').toBeGreaterThan(20);

// ✅ Verify INITIAL state trước khi test transition
await expect(checkbox, 'Should START unchecked').not.toBeChecked();
await checkbox.click();
await expect(button, 'Should BECOME enabled').toBeEnabled();
```

**Key:** Test phải FAIL nếu có bug. Nếu test pass khi field empty/"undefined" → Test "cho có"

---

## 2️⃣ CHỈ TEST THEO TÀI LIỆU

### ❌ Lỗi: Thêm External Knowledge

```typescript
// ❌ Thêm WCAG AAA (KHÔNG có trong test-design)
expect(contrast).toBeGreaterThan(7);

// ❌ Test pixel positions (browser-dependent, không có trong test-design)
expect(userBox.x).toBeGreaterThan(356);
```

### ✅ Cách Đúng

```typescript
// ✅ Test design Line 156 says: "touch targets ≥44px"
expect(boundingBox.width, 'Per Line 156').toBeGreaterThanOrEqual(44);

// ✅ Test design Line 155 says: "AI messages left-aligned"
const flexDirection = await element.evaluate((el) => getComputedStyle(el).flexDirection);
expect(flexDirection, 'Per Line 155').toBe('row');
```

**Key:** Mỗi assertion PHẢI có `Per Line XXX` reference từ test-design hoặc API-DOC

---

## 3️⃣ TRÁNH PIXEL POSITIONS

### ✅ Check CSS Properties (Not Coordinates)

```typescript
// ✅ Check layout (viewport-independent)
const justifyContent = await element.evaluate((el) => getComputedStyle(el).justifyContent);
expect(justifyContent).toBe('flex-end'); // Right-aligned

// ✅ Check relative positions
const msg2StartsAfterMsg1 = msg2Box.y >= msg1Box.y + msg1Box.height;
expect(msg2StartsAfterMsg1).toBe(true);
```

---

## 4️⃣ UI TEST vs CONTENT TEST

**UI test:** Check render (field visible + has data)
**Content test:** Check quality (keywords, AI accuracy)

```typescript
// ✅ UI test: Check length (not keywords)
expect(audienceText?.trim().length, 'UI: verify populated').toBeGreaterThan(20);

// ❌ UI test KHÔNG check AI quality
expect(response).toContain('professional'); // ← Content test responsibility
```

---

## 5️⃣ KHÔNG DUPLICATE CODE (DRY)

```typescript
// ✅ Reuse shared data
import { getContextualAnswersArray } from '../../../../src/refinement/test-data';
const answers = getContextualAnswersArray();

// ❌ KHÔNG hardcode trong test file
const answers = ['Answer 1...', 'Answer 2...'];
```

---

## 6️⃣ CHỈ TEST P0 TRONG P0 FILE

```
✅ tests/api/guest-refinement/
├── P0-session-management.spec.ts  (P0 ONLY)
├── P1-edit-question.spec.ts       (P1 ONLY)
└── P2-edge-cases.spec.ts          (P2 ONLY)
```

---

## 7️⃣ TYPESCRIPT TYPE SAFETY

### ❌ Lỗi: Dùng `any`/`unknown`

```typescript
// ❌ Dùng any (unsafe)
const body = await response.json(); // Type: any

// ❌ Dùng unknown (quá generic)
const body = (await response.json()) as unknown;
```

### ✅ Cách Đúng: Inline Interface

```typescript
// ✅ Cast sang inline interface với built-in types
const body = (await response.json()) as { error?: object; success?: boolean };
if (body.error) {
    expect(body.success).toBe(false);
}
```

**Key:** Use built-in types: `object`, `string`, `number`, `boolean`

---

## 8️⃣ TEST FAILS ≠ TEST SAI

### Decision Tree When Test Fails

```
Test Fails
│
├─ Step 1: Test follows test-design?
│  ├─ YES → ✅ Test CORRECT → Backend BUG
│  └─ NO  → ❌ Test WRONG → Fix test
│
├─ Step 2: Backend matches test-design?
│  ├─ YES → Review test logic
│  └─ NO  → ❌ Backend BUG → Log bug
│
└─ Step 3: API-DOC documents this?
   ├─ YES → Backend team misread spec
   └─ NO  → Documentation gap → Ask backend update
```

**CRITICAL:**

- ✅ **If test follows test-design → Test ALWAYS CORRECT**
- ❌ **NEVER change test to pass when backend wrong**

### Test Fail Workflow — `.fixme()` vs `.skip()` vs Fix

Sau khi `run-test-mark-fixme.sh` hook auto-mark fail tests bằng `.fixme()`, developer phải triage:

```
Test fail (đã auto-marked .fixme)
│
├─ A. Root cause = TEST LOGIC SAI (assertion sai, factory sai, sai endpoint)
│   → Fix logic → Xoá `.fixme()` → Re-run → PASS
│   → KHÔNG để .fixme() khi sửa được trong PR
│
├─ B. Root cause = BACKEND BUG (test đúng theo test-design, BE deviation)
│   → GIỮ `.fixme()` để CICD không fail
│   → Log bug theo `docs/templates/log-bug-api-template.md`
│   → Link bug ticket ở comment trên `.fixme()`:
│       test.fixme(  // BUG-#1234 — BE trả 500 thay vì 401 cho expired token
│         "expired token → 401",
│         { tag: ["@P0", "@BE", "@Function"] },
│         async () => { ... }
│       );
│   → Khi BE fix → xoá `.fixme()` + close bug
│
├─ C. Root cause = REQUIREMENT ĐỔI (test design outdated)
│   → Update test-design TRƯỚC (Hierarchy of Truth #1)
│   → Update test code theo design mới → Xoá `.fixme()`
│   → KHÔNG sửa test rồi mới quay lại update design
│
└─ D. Root cause = MÔI TRƯỜNG / FLAKY (test pass local, fail CI; race condition; data dirty)
    → `.skip()` (KHÔNG `.fixme()`) + comment lý do + assign owner debug
    → Vd: test.skip(  // FLAKY — race condition khi parallel >4 workers
              "concurrent updates", ...
            );
    → Add tag `@flaky` để CICD selective exclude
```

### `.fixme()` vs `.skip()` — quyết định nhanh

| Tình huống | Annotation | Lý do |
|---|---|---|
| Fail có bug ticket | `test.fixme()` | Track như work-in-progress, vẫn xuất hiện trong report |
| Fail vì BE chưa implement | `test.fixme()` | Test đúng theo spec, chờ BE catch up |
| Flaky / race condition | `test.skip()` + `@flaky` tag | KHÔNG track như "có bug", chờ debug môi trường |
| Test legacy không còn relevant | XOÁ test | KHÔNG `.skip()` mãi |
| Đang refactor — tạm tắt | `test.skip()` | Có comment "WIP — re-enable in PR #xxx" |

### CICD behavior khác nhau

| Annotation | Report show | Pre-merge gate | Coverage metric |
|---|---|---|---|
| `test.fixme()` | ✅ Hiện như "fixme" (orange) | KHÔNG block | Tính là "not run" |
| `test.skip()` | ⚠ Hiện như "skipped" (gray) | KHÔNG block | Tính là "skipped" |
| (xoá test) | Không hiện | N/A | Không tính |

→ Default: `.fixme()` cho bug-driven, `.skip()` cho env-driven. Tránh `.skip()` cho bug vì che trace.

---

## 9️⃣ SERVICE LAYER INTEGRATION (NEW)

**Learned from:** P2 Review (16 issues fixed: 10 critical TypeScript errors)

### 🔴 Common Errors (62.5% of P2 issues)

| Error                        | Frequency | Example                                      |
| ---------------------------- | --------- | -------------------------------------------- |
| Extra `accessToken` param    | 🔴 37.5%  | Not all methods accept accessToken           |
| Wrong payload structure      | 🟠 18.75% | String instead of object                     |
| Wrong parameter order        | 🟠 12.5%  | Boolean in wrong position                    |
| Wrong method name            | 🟠 12.5%  | `captureEmail` doesn't exist → `attachEmail` |
| Extra `expectedStatus` param | 🟠 12.5%  | Only Raw methods accept this                 |

### ✅ Prevention Steps (Before Calling Service)

**STEP 1: Read Service Signature**

```typescript
// Mở file: src/guest-refinement/guest-refinement.service.ts
// Search: "export async function methodName"
export async function updateConcept(
    request: APIRequestContext,     // 1
    sessionId: string,               // 2
    fingerprint: string,             // 3
    payload: GuestUpdateConceptPayload, // 4
    guestId?: string,                // 5 (optional)
    testName?: string                // 6 (optional) ← NO accessToken!
): Promise<...>
```

**STEP 2: Count Parameters**

- Required: 4 params
- Optional: 2 params
- Total: 6 params ← NOT 7!

**STEP 3: Check Payload Structure (API-DOC)**

```typescript
// API-DOC line 1791: POST /refinements/guest/{sessionId}/email
// Payload: { email*: string }

// ✅ CORRECT: Object
{
    email: 'user@example.com';
}

// ❌ WRONG: Primitive
('user@example.com');
```

**STEP 4: Call with Correct Signature**

```typescript
// ✅ CORRECT
const result = await GuestRefinementService.updateConcept(
    request,
    sessionId,
    fingerprint,
    payload,
    guestId,
    testName
    // ✅ 6 params - NO accessToken
);

// ❌ WRONG: 7 params
const result = await GuestRefinementService.updateConcept(
    request,
    sessionId,
    fingerprint,
    payload,
    guestId,
    testName,
    accessToken
    // Error: Expected 4-6 arguments, but got 7
);
```

### 🔧 Quick Debug TypeScript Errors

```
Error: Expected 4-6 arguments, but got 7
```

**Fix Steps:**

1. Open service file → Find method definition
2. Count params in signature (4 required + 2 optional = 6)
3. Count params in test call (7) ← TOO MANY
4. Remove extra param (accessToken not in signature)
5. Run `npx tsc --noEmit file.spec.ts` → Verify 0 errors

### 📋 Service Layer Checklist (8 Steps)

- [ ]   1. **MỞ service file** → Find method definition
- [ ]   2. **ĐẾM parameters** (required + optional)
- [ ]   3. **GHI CHÚ parameter types** (string, object, boolean)
- [ ]   4. **GHI CHÚ parameter order** (especially optional)
- [ ]   5. **KIỂM TRA method name** (exact spelling, no typo)
- [ ]   6. **ĐỌC API-DOC** payload structure (if payload param)
- [ ]   7. **THÊM comment** reference API-DOC line
- [ ]   8. **RUN TypeScript** compilation → Verify 0 errors

---

## 📋 CHECKLIST KHI VIẾT TEST MỚI (41 Items)

### Pre-Implementation (6)

- [ ]   1. Đọc test design document (tìm line number)
- [ ]   2. Xác định priority (P0/P1/P2)
- [ ]   3. Check test data đã có trong `test-data.ts` chưa?
- [ ]   4. Xác định scope: UI test hay Content test?
- [ ]   5. **ĐỌC service method signature** (nếu gọi service layer)
- [ ]   6. **ĐỌC API-DOC payload structure** (nếu có payload)

### During Implementation (9)

- [ ]   7. Mỗi test CHỈ verify 1 requirement từ test design
- [ ]   8. Mỗi assertion có comment line number reference
- [ ]   9. KHÔNG add external knowledge (WCAG, Material Design)
- [ ]   10. KHÔNG check pixel positions
- [ ]   11. Check CSS properties thay vì coordinates
- [ ]   12. UI test: CHỈ check length, KHÔNG check keywords
- [ ]   13. **ĐẾM parameters khi gọi service methods**
- [ ]   14. **VERIFY method name exists** (TypeScript IntelliSense)
- [ ]   15. **CHECK payload structure** matches API-DOC

### Verification Against "Cho Có" (5)

- [ ]   16. Test fails nếu field empty? (Not just visibility)
- [ ]   17. Test fails nếu field = "undefined"?
- [ ]   18. Test fails nếu initial state sai?
- [ ]   19. Test fails nếu state transition không work?
- [ ]   20. Test có thể pass khi bug exists? → ❌ "Cho có"

### Code Quality (5)

- [ ]   21. Reuse test data từ `test-data.ts`
- [ ]   22. No duplicate test data trong test file
- [ ]   23. No duplicate tests
- [ ]   24. Test đúng file (P0 in P0 file, không mix)
- [ ]   25. **TypeScript Type Safety:** KHÔNG dùng `any`/`unknown`
    - ✅ Cast: `as { error?: object }`
    - ❌ NO: `as any`, `as unknown`

### Service Layer Integration (6)

- [ ]   26. **Service signature correct?** Đọc signature, đếm params
- [ ]   27. **Method name exists?** Use IntelliSense, no typos
- [ ]   28. **Payload structure correct?** Check API-DOC, use object
- [ ]   29. **Parameter order correct?** Check signature, optional params
- [ ]   30. **No extra accessToken/expectedStatus?** Only if method accepts
- [ ]   31. **RUN TypeScript** (`npx tsc --noEmit file.spec.ts`)

### Final Review (5)

- [ ]   32. Run test → Verify catches bugs
- [ ]   33. Manually break implementation → Test should fail
- [ ]   34. Review: Có assertion "cho có" không?
- [ ]   35. Review: Có add external knowledge không?
- [ ]   36. **Review: Service calls correct?** No TypeScript errors

### When Test Fails (5)

- [ ]   37. **CRITICAL:** Test follows test-design?
    - YES → ✅ Test CORRECT → Log backend bug
    - NO → ❌ Test WRONG → Fix test
- [ ]   38. Backend matches test-design?
    - YES → Review test logic
    - NO → ❌ Backend BUG
- [ ]   39. API-DOC documents this?
    - NO → Documentation gap
    - YES → Backend misread spec
- [ ]   40. **NEVER:** Change test to pass when backend wrong
- [ ]   41. **NEVER:** Skip test vì API-DOC không document

---

## 📊 STATISTICS & RESULTS

### P0/P1/P2 Test Reviews

| File               | Tests  | Issues Fixed     | Quality     | Status    |
| ------------------ | ------ | ---------------- | ----------- | --------- |
| P0-chat-interface  | 3      | Multiple         | ✅ 100%     | DONE      |
| P0-concept-summary | 5      | 10 removed       | ✅ 100%     | DONE      |
| P0-email-capture   | 4      | BUG-02.5-003     | ✅ 100%     | DONE      |
| P2-edge-cases      | 4      | 7 (4 critical)   | ✅ 100%     | DONE      |
| P2-business-rules  | 4      | 4 (4 critical)   | ✅ 100%     | DONE      |
| P2-validation      | 3      | 5 (3 critical)   | ✅ 100%     | DONE      |
| **TOTAL**          | **23** | **16 P2 issues** | ✅ **100%** | **READY** |

### P2 Review Impact

- **TypeScript Errors:** 17 → 0
- **Service Method Accuracy:** 76% → 100%
- **Common Error:** 62.5% parameter-related (extra accessToken, wrong order, wrong payload)

---

## 🚀 QUICK START

### Khi Viết Test Mới

1. ✅ Đọc test-design document → Find line numbers
2. ✅ Check test-data.ts → Reuse shared data
3. ✅ **Đọc service signature** → Count params, check types
4. ✅ **Đọc API-DOC** → Payload structure, reference line numbers
5. ✅ Write test → Apply 9 rules
6. ✅ Run TypeScript → Verify 0 errors
7. ✅ Run test → Verify catches bugs

### Khi Test Fails

1. ❓ Test follows test-design? → **YES** → Backend bug (log it)
2. ❓ Backend matches test-design? → **NO** → Backend bug (log it)
3. ❌ **NEVER change test** to pass when backend wrong

### Khi Review Test

1. ✅ Check 9 rules compliance
2. ✅ Check 41 checklist items
3. ✅ Run TypeScript compilation
4. ✅ Run ESLint
5. ✅ Verify test catches bugs (manually break implementation)

---

## 📚 REFERENCE - DETAILED RULES

### Rule #1-7: See sections above for details

### Rule #8: Decision tree in section above

### Rule #9: Service integration guide in section above

**Real Examples:** See P2 review reports in `docs/sprint3/squad-idea/`:

- P2-edge-cases-review-report.md
- P2-business-rules-review-report.md (from earlier review)
- P2-validation-review-report.md
- P2-COMPLETE-REVIEW-SUMMARY.md

---

**Generated by:** User (TAN) + Claude Code (Murat - TEA Agent)
**Last Updated:** 2026-01-13 (Optimized for token efficiency)
**Version:** 2.0 (Condensed from 1337 lines → ~500 lines)

**Core Principles:**

1. "toi can chat luong chu dau can ban co tinh cho test pass dau"
2. "Test follows test-design → Test ALWAYS CORRECT, backend ALWAYS WRONG"
3. "LUÔN đọc service method signature - KHÔNG giả định parameters"
