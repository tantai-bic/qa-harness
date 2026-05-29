# Common — Decision Table

Áp dụng cho **cả API + E2E**. Khi có multi-condition AND/OR logic → liệt kê truth table → 1 test per row.

## Phương pháp

1. List input **conditions** (Boolean / categorical).
2. Build truth table 2^N rows (or reduced if infeasible combos).
3. Mark **don't-care** (`*`) khi 1 condition dominates.
4. 1 test per row với expected output rõ ràng.
5. Test name = condition combo.

## Template

Ví dụ Phase B traffic light zone:

| #   | reach ≥ 50 | rate ≥ 20% | rate 10-19% | Expected zone         |
| --- | ---------- | ---------- | ----------- | --------------------- |
| 1   | T          | T          | -           | GREEN                 |
| 2   | T          | F          | T           | YELLOW                |
| 3   | T          | F          | F           | RED                   |
| 4   | F          | \*         | \*          | `null` (insufficient) |

→ 4 test cases (TC-001..004), mỗi case set up data đúng partition.

## Ví dụ project: Poll Result Submit (Story 03.2.4)

10 scenarios decision table — xem MEMORY ref `project_poll_result_submit_cases.md`.

Conditions:

- `pollUrl` set?
- Result already submitted?
- Tactic locked?
- Validation status (`running` / `completed` / `cancelled`)?
- User is creator?

→ 10 rows trong test design → TC-4.27..4.39 specs.

## Ví dụ project: Login

| email valid | password match | account locked | email verified | Expected                                 |
| ----------- | -------------- | -------------- | -------------- | ---------------------------------------- |
| T           | T              | F              | T              | 200 OK                                   |
| T           | T              | F              | F              | 200 OK (but some endpoints later reject) |
| T           | T              | T              | \*             | 403 Locked                               |
| T           | F              | F              | \*             | 401                                      |
| F           | \*             | \*             | \*             | 400 (format)                             |

## Reduce combinatorial explosion

Khi N conditions → 2^N rows quá nhiều. Strategies:

| Technique                | Apply                                                              |
| ------------------------ | ------------------------------------------------------------------ |
| **Don't-care** (`*`)     | Khi 1 condition dominates outcome, các condition khác không matter |
| **Equivalence collapse** | Merge rows nếu BE treat identical                                  |
| **Pairwise testing**     | Cover all pairs of N conditions (sqrt(2^N) tests)                  |
| **Risk-based prune**     | Skip rows business-impossible với explicit rationale               |

## Checklist

```
☐ Identified all input conditions (Boolean / categorical)
☐ Built truth table 2^N rows (or reduced if infeasible combos)
☐ Marked don't-care (*) khi 1 condition dominates
☐ Mỗi row 1 test case với expected output rõ
☐ Test name = condition combo (vd "TC-002 [reach≥50, rate=15%]")
☐ Rationale documented khi prune rows
```

## See also

- [equivalence-partition.md](./equivalence-partition.md) — partition values rồi cartesian product
- [state-transition.md](./state-transition.md) — transition guards thường multi-condition
- MEMORY `project_poll_result_submit_cases.md`
