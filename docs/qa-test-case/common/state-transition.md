# Common — State Transition Testing

Áp dụng cho **cả API + E2E**. Vẽ **state machine** rồi test mỗi transition (valid + invalid).

## Phương pháp

1. Identify all **states** (vd `draft`, `running`, `completed`).
2. Identify all **transitions** (event → from-state → to-state).
3. Categorize **valid** vs **invalid** transitions.
4. 1 test per transition + 1 test per invalid attempt.

## Diagram pattern

```
[StateA] ──event1──► [StateB] ──event2──► [StateC]
   │                    │                    │
   └─(invalid back)     ├──event3──► [StateD]
                        └──event4──► [StateE]
```

## Ví dụ project — Phase B validation state machine

```
draft ──refining-completion──► running ──(auto, hết duration)──► completed
  │                              │
  └─(no manual back)             ├──pause──► paused ──resume──► running
                                 └──cancel──► cancelled
```

## Test cases mỗi state machine

| Test                                     | Mục đích                                               |
| ---------------------------------------- | ------------------------------------------------------ |
| Valid transition (`draft → running`)     | Happy path: POST `/refining-completion` từ draft → 201 |
| Invalid transition (`running → running`) | Re-call `/refining-completion` → 409 `ERR_1001`        |
| Setup API trong wrong state              | POST `/tactics` khi `status=running` → 4xx             |
| Auto transition                          | Wait duration → BE auto `running → completed`          |
| Terminal state behavior                  | `completed`: read APIs work, setup APIs reject         |
| Reversibility                            | `completed → draft` impossible → seed fresh            |

## Examples khác trong project

| State machine      | Doc                                                                   |
| ------------------ | --------------------------------------------------------------------- |
| Phase B validation | [`docs/roadmap/campaign/phaseB.md`](../../roadmap/campaign/phaseB.md) |
| Refinement session | `in_progress → completed → confirmed`                                 |
| Recipient email    | `sent → opened → clicked → registered` (or `bounced`/`failed`)        |
| Lockout            | `unlocked → 5 failed → locked (30min) → unlocked`                     |
| Token              | `valid → refresh → new valid` / `valid → logout → invalid`            |

## Checklist

```
☐ Identified all states (e.g. draft, running, completed, paused, cancelled)
☐ Mỗi valid transition có 1 happy path test
☐ Mỗi invalid transition có 1 negative test (verify error code)
☐ Auto-transition (timer-based) covered hoặc explicit fixme với rationale
☐ Read-only behavior trong terminal state verified
☐ Reversibility documented (one-way vs reversible)
```

## See also

- [decision-table.md](./decision-table.md) — multi-condition transition guards
- [`docs/roadmap/campaign/phaseB.md`](../../roadmap/campaign/phaseB.md) § "Setup API gate" — Phase B setup gate enforce qua state
