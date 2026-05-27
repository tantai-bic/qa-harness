# Common — Output Artifacts

File structure + naming convention cho test case bộ.

## File structure cho 1 story

```
docs/sprint_X/epic-XX-feature-name/
├── story-XX.YY/
│   ├── story-spec.md          ← business requirements
│   ├── test-plan.md           ← strategy
│   ├── test-design.md         ← decision tables + boundary + state machine
│   ├── bdd-test-scenarios.md  ← Given-When-Then
│   └── api-contract.md        ← BE contract
├── analysis-us-vs-figma.md
└── checklist-pre-dev.md

tests/
├── api/{module}/story-XX.YY/
│   ├── P0-{critical}.spec.ts  ← P0 only — Rule #6
│   ├── P1-{important}.spec.ts
│   └── P2-{nice-to-have}.spec.ts
└── e2e/{module}/
    ├── P0-{golden-path}.spec.ts
    └── P1-{state-transitions}.spec.ts

src/{module}/                  ← service + factory + types + fixtures
├── *.service.ts               ← API operations (F-1 — no direct request.post)
├── *.factory.ts               ← test data generation
├── *.types.ts
└── seed/*.helper.ts           ← fresh-state seeding helpers
```

## Naming convention

| Pattern              | Example                                                        |
| -------------------- | -------------------------------------------------------------- |
| TC ID (cross-spec)   | `TC-API-001` · `TC-E2E-042`                                    |
| TC ID (story-scoped) | `TC-4.20` (Story 03.2.4 — 4 là epic number)                    |
| Test title           | `[TC-API-001] [P0] Description of behavior`                    |
| Spec file            | `P0-result-integrity.spec.ts` · `P1-state-transitions.spec.ts` |
| Service file         | `{domain}.service.ts` (vd `signup.service.ts`)                 |
| Factory file         | `{domain}.factory.ts`                                          |
| Fixture file         | `{domain}.fixture.ts` · `e2e-{flow}.fixture.ts`                |
| Selector file        | `{page}.selectors.ts`                                          |
| Helper file          | `{domain}.helper.ts` (placed in `src/`, NOT in `tests/`)       |

## Priority rules (Rule #6)

| Priority | Trong file     | Mục đích                                |
| -------- | -------------- | --------------------------------------- |
| **P0**   | `P0-*.spec.ts` | Critical paths — must pass before merge |
| **P1**   | `P1-*.spec.ts` | Important features — should pass        |
| **P2**   | `P2-*.spec.ts` | Nice-to-have — can defer                |

❌ KHÔNG mix P0/P1/P2 trong cùng file.

## Hook enforce file locations

| Hook                             | Block                                            | Lý do                                                             |
| -------------------------------- | ------------------------------------------------ | ----------------------------------------------------------------- |
| `enforce-helper-location.sh`     | Helper/.fixture/.factory/.service trong `tests/` | Helpers phải ở `src/` để shareable + properly typed               |
| `enforce-json-debug-location.sh` | Debug \*.json ở project root                     | Chỉ canonical configs (package.json, tsconfig\*.json, etc.) allow |
| `restrict-global-test-run.sh`    | `npx playwright test` no filter                  | Force `--project=api` or path filter                              |

## Output checklist

```
☐ TC-ID assigned (`TC-XXX-NNN`)
☐ Priority đúng file (P0/P1/P2)
☐ Naming convention `[TC-...] [Px] desc`
☐ Service layer calls (no direct request.post — F-1)
☐ Factory cho test data (no hardcode — F-2)
☐ Helpers ở src/ không phải tests/
☐ TypeScript compiles `npx tsc --noEmit`
☐ Anti-pattern hooks pass
```

## See also

- [pre-data.md](./pre-data.md)
- [pre-condition.md](./pre-condition.md)
- [`/CLAUDE.md`](../../../../CLAUDE.md) — F-1..F-6 rules
