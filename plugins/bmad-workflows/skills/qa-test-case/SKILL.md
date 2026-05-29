---
name: qa-test-case
description: Test design toolkit cho 1 feature/story — 14 module độc lập (common/backend/frontend). Bao gồm pre-data, pre-condition, happy/bad/edge case, BVA, equivalence partition, decision table, state transition, security, injection-XSS, service integration, FE visual states, interactions, XSS rendering, anti-patterns. Dùng khi thiết kế test cases cho API hoặc E2E test, hoặc khi cần technique cụ thể (boundary, equivalence, decision table).
---

# QA Test Case — Skill Index

Test design toolkit cho 1 feature/story. 14 module độc lập, tách FE/BE.

## Hierarchy of Truth

`test-design > test code > backend > API-DOC.md` — test ALWAYS đúng nếu follow test-design. BE wrong → log bug, **KHÔNG sửa test**.

## Module map

```
skills/qa-test-case/
├── SKILL.md                          ← index (file này)
├── common/                           ← layer-agnostic
│   ├── pre-data.md                   factory + unique IDs
│   ├── pre-condition.md              state probe trước assert (F-3)
│   ├── happy-case.md ⭐              P0 critical successful path (2-5 representative)
│   ├── bad-case.md ⭐                reject path (400/401/403/404/409/422) + parseErrorResponse
│   ├── edge-case.md ⭐               P2 unusual valid (concurrency/unicode/large/idempotent)
│   ├── boundary-value.md             6-value BVA (MIN-1/MIN/MIN+1/MAX-1/MAX/MAX+1)
│   ├── equivalence-partition.md      valid/invalid partitions
│   ├── state-transition.md           state machine valid/invalid + auto transitions
│   ├── decision-table.md             2^N truth table
│   └── output-artifacts.md           file structure + naming
├── backend/                          ← API
│   ├── security.md                   401/403/IDOR/CSRF/JWT/cookie
│   ├── injection-xss.md              SQLi/XSS/path traversal/cmd injection
│   └── service-integration.md        Rule #9 service signature + HTTP semantics
└── frontend/                         ← E2E UI
    ├── visual-states.md              9 states + responsive
    ├── interactions.md               form/modal/keyboard/i18n
    ├── xss-rendering.md              DOM XSS + 8 payload variants
    └── anti-patterns.md              5 critical + 7 minor FE anti-patterns
```

## Reading order (design 1 feature)

| #   | Module                                                            | Purpose                                    |
| --- | ----------------------------------------------------------------- | ------------------------------------------ |
| 1   | [common/pre-data](./common/pre-data.md)                           | Factory + unique IDs                       |
| 2   | [common/pre-condition](./common/pre-condition.md)                 | State probe                                |
| 3   | [common/happy-case](./common/happy-case.md) ⭐                    | P0 critical path                           |
| 4   | [common/bad-case](./common/bad-case.md) ⭐                        | 6 reject categories                        |
| 5   | [common/boundary-value](./common/boundary-value.md)               | BVA                                        |
| 6   | [common/equivalence-partition](./common/equivalence-partition.md) | Partitions                                 |
| 7   | [common/state-transition](./common/state-transition.md)           | State machine                              |
| 8   | [common/decision-table](./common/decision-table.md)               | Multi-condition                            |
| 9   | [common/edge-case](./common/edge-case.md) ⭐                      | P2 unusual valid                           |
| 10a | [backend/](./backend/)                                            | API: security/injection/service            |
| 10b | [frontend/](./frontend/)                                          | E2E: states/interactions/xss/anti-patterns |
| 11  | [common/output-artifacts](./common/output-artifacts.md)           | Naming + priority files                    |

## Quick-pick

| Đang viết gì?       | Đọc                                                                                                                                 |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| API test            | pre-data + pre-condition + happy-case + bad-case + boundary + equivalence → [backend/](./backend/)                                  |
| E2E test            | pre-data + pre-condition + happy-case + bad-case → [frontend/](./frontend/)                                                         |
| P0 happy            | [happy-case](./common/happy-case.md)                                                                                                |
| P0 reject           | [bad-case](./common/bad-case.md) + [backend/security](./backend/security.md)                                                        |
| P2 edge             | [edge-case](./common/edge-case.md)                                                                                                  |
| Multi-condition     | [decision-table](./common/decision-table.md)                                                                                        |
| State machine       | [state-transition](./common/state-transition.md) + [roadmap/campaign](../../../docs/roadmap/campaign/)                                         |
| Security test       | [backend/security](./backend/security.md) + [injection-xss](./backend/injection-xss.md)                                             |
| XSS test            | [backend/injection-xss](./backend/injection-xss.md) (BE escape) + [frontend/xss-rendering](./frontend/xss-rendering.md) (FE escape) |
| UI states           | [frontend/visual-states](./frontend/visual-states.md)                                                                               |
| Form/modal/keyboard | [frontend/interactions](./frontend/interactions.md)                                                                                 |
| Refactor test       | [frontend/anti-patterns](./frontend/anti-patterns.md) + [backend/service-integration](./backend/service-integration.md)             |

## Golden Rules

Tham chiếu [TEST-QUALITY-CHECKLIST.md](../test-quality-checklist/SKILL.md) (9 rules + 41 items):

1. Chống "cho có" — verify ACTUAL behavior, không chỉ visibility
2. Test theo test-design — không tự suy WCAG/Material Design
3. Tránh pixel positions — dùng CSS/role/text
4. UI test check render, content quality tách riêng
5. DRY — reuse `test-data.ts`
6. **Split P0/P1/P2 file** (CI/CD grep selective)
7. Type safety — no `any`/`unknown`
8. Test fails ≠ test sai — KHÔNG sửa test khi BE wrong
9. Service signature — read FIRST trước khi import

## Master Checklist — bộ test hoàn chỉnh

```
PRE-DESIGN
☐ Đọc test-design.md (Hierarchy of Truth)
☐ Đọc API-DOC.md với line refs
☐ Identify phase (A/B/C/D) — đọc roadmap/campaign/phaseX.md § Upstream

SETUP (common/)
☐ Factories + unique IDs + edge values → pre-data.md
☐ State probe trước assert (F-3) → pre-condition.md
☐ Cleanup path documented

COVERAGE METHODS (common/)
☐ Happy: 2-5 representative → happy-case.md
☐ Bad: 6 categories (400/401/403/404/409/422) → bad-case.md
☐ Boundary: 6 cases per constraint → boundary-value.md
☐ Equivalence: 1 valid + N invalid per field → equivalence-partition.md
☐ State transition (nếu có state machine) → state-transition.md
☐ Decision table (multi-condition) → decision-table.md
☐ Edge: concurrency/idempotency/unicode/large (P2) → edge-case.md

BACKEND TESTS (backend/)
☐ Security: 401/403/429/IDOR/CSRF/JWT → security.md
☐ Injection: SQLi/XSS stored/path traversal/cmd → injection-xss.md
☐ Service signature đúng (Rule #9) → service-integration.md
☐ HTTP status semantics (200 vs 404 vs 200+empty)

FRONTEND TESTS (frontend/)
☐ 9 visual states + responsive → visual-states.md
☐ Form/modal/keyboard interactions → interactions.md
☐ XSS rendering 8 variants → xss-rendering.md
☐ Anti-patterns avoided → anti-patterns.md

QUALITY GATES (TEST-QUALITY-CHECKLIST.md)
☐ Rule #1 verify ACTUAL behavior
☐ Rule #2 chỉ test theo test-design
☐ Rule #5 DRY reuse test-data.ts
☐ Rule #6 split priority file
☐ Rule #7 no `any`/`unknown`
☐ Rule #9 service signature

OUTPUT
☐ TC-ID format `TC-XXX-NNN`
☐ Priority đúng file
☐ Service layer calls (no direct request)
☐ npx tsc --noEmit pass
```

## References

- [TEST-QUALITY-CHECKLIST.md](../test-quality-checklist/SKILL.md) — 9 rules SoT
- [qa-engineer/skill.md](../qa-engineer/SKILL.md) — Code patterns (service/factory/fixture)
- [roadmap/README.md](../../../docs/roadmap/README.md) — Phase A/B/C/D state machines
- [\_bmad-output/project-context.md](../../../_bmad-output/project-context.md) — Anti-patterns + security
- [api/](../../../docs/api/) — BE contracts
- [templates/](../../../docs/templates/) — Story/test-plan/bug-log templates
