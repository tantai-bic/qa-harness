# Playwright QA Workflow — Roadmap, Scope & Process

> Canonical reference cho QA workflow: đọc roadmap trước khi code, scope discipline,
> và quy trình làm việc. Hook `enforce-roadmap-reading.sh` tự động nhắc khi
> detect implement/test request.

## 1. Roadmap Reading Workflow

### Tại sao bắt buộc đọc roadmap

Features trong một hệ thống phụ thuộc nhau theo chain. Nếu viết test mà không biết
upstream state → test sẽ fail do thiếu precondition, không phải do bug thực.

### Khi nào trigger

Hook tự động nhắc khi prompt có:
- **VN:** tính năng, implement, viết test, tạo test, scaffold, kịch bản
- **EN:** implement, build feature, write test, create test, test plan, spec
- **Path:** tests/api, tests/e2e, src/
- **Generic:** roadmap, phase, lifecycle, upstream, downstream

### Workflow bắt buộc

```
① Read  docs/roadmap/README.md          ← index, xác nhận feature mapping
② Read  doc của feature target          ← chú ý § "Upstream"
③ RECURSION: mỗi upstream trong ②      ← read doc upstream đó
   → lặp § "Upstream" cho đến gốc (no upstream)
```

**Lý do recursion:** Feature downstream chỉ hoạt động đúng nếu upstream seed đúng state.
Thiếu bước này → test fail vì missing seed data, không phải BE bug.

### Consumer roadmap structure (example)

```
docs/roadmap/
├── README.md                   Index: list features + state machine
├── phase-a/
│   └── feature-login.md        § Upstream: none | § State: authenticated=true
├── phase-b/
│   └── feature-dashboard.md    § Upstream: feature-login | § State: dashboard.loaded=true
└── phase-c/
    └── feature-export.md       § Upstream: feature-dashboard | § State: ...
```

Đọc `feature-export.md` → phải đọc ngược `feature-dashboard.md` → `feature-login.md`.

---

## 2. Scope Discipline

### Rule: 1 module per task (default)

**❌ SAI — tự expand scope:**
```
User: "Viết test cho login feature"
Claude: *viết test cho login + dashboard + profile luôn*
```

**✅ ĐÚNG — đúng scope được yêu cầu:**
```
User: "Viết test cho login feature"
Claude: *chỉ viết tests/api/auth/login/ — stop*

User: "Viết test cả phase A"
Claude: *viết toàn bộ phase A — user đã nói rõ*
```

**Module detection** (tự động từ prompt):
- Path pattern: `tests/api/{domain}` → domain = module
- Keyword: "cho module X", "for feature X", "X.spec.ts"
- Fallback: hỏi user nếu không rõ

---

## 3. Test Session Workflow

Quy trình chuẩn cho mỗi test-writing session:

```
① Read roadmap docs           (enforce-roadmap-reading hook nhắc)
② Read skill docs             (preload-playwright-context hook load 1×)
   • playwright-test-organization/SKILL.md  ← rule #6, service/factory
   • playwright-setup/SKILL.md              ← required structure
   • skills/test-quality-checklist/SKILL.md ← 9 quality rules
③ Grep src/{module}/ → tìm service + factory đã có
④ Write test files            (split P0/P1/P2 — Rule #6)
⑤ Run test                    (npx playwright test <file>)
⑥ Classify: pass/fixme/fail
⑦ Report với evidence        ("8 pass, 1 fixme, 0 fail")
```

---

## 4. QA Decision Framework

### Test design document là source of truth

Khi có conflict giữa test expectation và BE behavior:

| Situation | Action |
|-----------|--------|
| Test fail, BE response khác design | Log bug, KHÔNG sửa test |
| Test fail, test code sai logic | Fix test |
| Test pass nhưng output sai design | Tạo test case đúng, log bug |
| API-DOC outdated vs BE behavior | Follow test-design, note discrepancy |

### Khi nào được sửa test (không phải log bug)

- Test logic sai (sai assertion, sai import, sai payload)
- Test setup broken (fixture missing, factory wrong shape)
- Test scope creep (test cái không liên quan đến feature)

### KHÔNG được sửa test để

- Pass BE response sai với design
- Work around missing seed data (fix seed thay vì bypass test)
- Hide flaky network behavior (fix underlying cause)

---

## 5. CICD Tag Convention

Mọi spec file phải có đủ tags (enforce bởi `enforce-spec-tags.sh`):

```ts
test.describe('@P0 @BE @Smoke — Login success', () => {
  // PRIORITY tag: @P0 / @P1 / @P2 / @P3
  // LAYER tag:    @BE (API/backend) | @FE (E2E/frontend)
  // TYPE tag ≥1:  @Smoke | @Sanity | @Regression | @Function | @UI | @UX
});
```

**Thiếu tag → `enforce-spec-tags.sh` BLOCK write.**

---

## 6. Bypass Reference

| Env var | Scope |
|---------|-------|
| `SKIP_ROADMAP_READING=1` | Skip roadmap enforcement hook |
| `SKIP_TEST_ORCHESTRATION=1` | Skip test orchestration hook |
| `SKIP_PLAYWRIGHT_PRELOAD=1` | Skip skill preload hook |
| `SKIP_PLAYWRIGHT_SETUP=1` | Skip setup check hook |
| `SKIP_HOOKS=1` | Master bypass (tất cả hooks) |
| `ROADMAP_TRIGGER_REGEX=<pattern>` | Custom trigger pattern cho roadmap hook |
| `MODULE_KEYWORDS=<space-sep>` | Custom module keywords cho orchestration hook |
