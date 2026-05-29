# Common — State Transition Testing

Áp dụng cho **cả API + E2E**. Vẽ **state machine** rồi test mỗi transition (valid + invalid).

## Phương pháp

1. Identify all **states** (vd `draft`, `running`, `completed`).
2. Identify all **transitions** (event → from-state → to-state).
3. Categorize **valid** vs **invalid** transitions.
3b. Identify **guard conditions** (transition chỉ valid khi điều kiện đúng — xem [decision-table.md](./decision-table.md)).
4. 1 test per transition + 1 test per invalid attempt.

## Diagram pattern

```
[StateA] ──event1──► [StateB] ──event2──► [StateC]
   │                    │                    │
   └─(invalid back)     ├──event3──► [StateD]
                        └──event4──► [StateE]
```

## Ví dụ project — Auth Session State Machine

```
logged_out ──[login success]──► active ──[logout]──► logged_out
                                  │
                                  └──[token_expire]──► expired ──[refresh_ok]──► active
                                                          │
                                                          └──[refresh_fail]──► invalid (terminal)
```

## Ví dụ project — Phase B validation state machine

```
draft ──refining-completion──► running ──(auto, hết duration)──► completed
  │                              │
  └─(no manual back)             ├──pause──► paused ──resume──► running
                                 └──cancel──► cancelled
```

## Test case matrix

| Test                                          | Mục đích                                                        |
| --------------------------------------------- | --------------------------------------------------------------- |
| Valid transition (`draft → running`)          | Happy path: POST `/refining-completion` từ draft → 201          |
| Valid transition (`active → expired`)         | Token expire event → state changes correctly                    |
| Valid transition (`expired → active`)         | Refresh success → restore active session                        |
| Invalid back-transition (`running → running`) | Re-call `/refining-completion` → 409 `ERR_1001`                 |
| Invalid back-transition (`completed → draft`) | Reverse one-way transition → 4xx error                          |
| Double-trigger same transition                | Fire same event twice → second call rejected (idempotency)      |
| Setup API trong wrong state                   | POST `/tactics` khi `status=running` → 4xx                     |
| Terminal state mutation attempt               | `invalid` session: any write → reject; read APIs still work     |
| Auto transition                               | Wait duration → BE auto `running → completed`                   |
| Read-only behavior trong terminal state       | `completed`: read APIs work, setup APIs reject                  |
| Reversibility                                 | `completed → draft` impossible → seed fresh                     |

## Auto-transition (timer/event-driven)

Khi transition xảy ra do timer hoặc external event (không phải direct API call):

- **(a) Preferred:** dùng test account short-TTL (vd expire=30s) để verify state thay đổi sau timeout — không mock timer.
- **(b) Fallback:** nếu TTL quá dài cho CI, mark `test.fixme()` với rationale: `// fixme: TTL=30min, needs short-TTL account — ticket #XXX`.
- **(c)** Trong transitional window: verify read APIs vẫn trả đúng data, write APIs reject từ state mới.

## Examples khác trong project

| State machine      | Doc                                                                              |
| ------------------ | -------------------------------------------------------------------------------- |
| Phase B validation | [`docs/roadmap/campaign/phaseB.md`](../../../../docs/roadmap/campaign/phaseB.md) |
| Refinement session | `in_progress → completed → confirmed`                                            |
| Recipient email    | `sent → opened → clicked → registered` (or `bounced`/`failed`)                  |
| Lockout            | `unlocked → 5 failed → locked (30min) → unlocked`                               |
| Token              | `valid → refresh → new valid` / `valid → logout → invalid`                      |

## Checklist

```
☐ Identified all states (e.g. draft, running, completed, paused, cancelled)
☐ Mỗi valid transition có 1 happy path test
☐ Mỗi invalid transition có 1 negative test (verify error code)
☐ Invalid back-transition, double-trigger, terminal mutation covered
☐ Guard conditions (multi-condition) modeled via decision-table.md
☐ Auto-transition: either covered hoặc @fixme với rationale
☐ Read-only behavior trong terminal state verified
☐ Reversibility documented (one-way vs reversible)
```

## See also
- [decision-table.md](./decision-table.md) — multi-condition transition guards
- [equivalence-partition.md](./equivalence-partition.md) — partition valid states as input classes
