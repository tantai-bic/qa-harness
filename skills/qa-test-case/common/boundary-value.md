# Common — Boundary Value Analysis (Giá trị biên)

Áp dụng cho **cả API + E2E** với bất kỳ constraint số/length/date/array.

## Phương pháp

Cho mỗi field constraint, test **6 values** quanh biên:

| Position  | Value     |
| --------- | --------- |
| Below min | `MIN - 1` |
| At min    | `MIN`     |
| Above min | `MIN + 1` |
| Below max | `MAX - 1` |
| At max    | `MAX`     |
| Above max | `MAX + 1` |

## Ví dụ thực tế trong project

| Field                           | Constraint    | Test values                               |
| ------------------------------- | ------------- | ----------------------------------------- |
| Signup password length          | 8-15 chars    | 7, 8, 9, 14, 15, 16                       |
| Validation `durationDays`       | 3-14          | 2, 3, 4, 13, 14, 15                       |
| Validation `platforms[]` count  | 1-6           | 0, 1, 2, 5, 6, 7                          |
| Funding goal                    | $100-$100,000 | $99, $100, $101, $99999, $100000, $100001 |
| Campaign title length           | 1-255 chars   | 0, 1, 2, 254, 255, 256                    |
| Tactics count                   | max 3         | 0, 1, 3, 4                                |
| Email recipients per validation | min 1         | 0, 1, 2 (no max enforced public)          |
| Poll `totalVotes`               | ≥ 0           | -1, 0, 1, max-int, max-int+1              |
| `preferredOptionPercent`        | 0-100         | -0.1, 0, 0.5, 99.5, 100, 100.1            |

## Boundary categories khác

| Category              | Edges to test                                                                                        |
| --------------------- | ---------------------------------------------------------------------------------------------------- |
| **Date/datetime**     | today, yesterday, future +1, past -1, far-future, far-past, ISO 8601 boundary `2099-12-31T23:59:59Z` |
| **Array length**      | empty `[]`, 1 item, N-1, N, N+1                                                                      |
| **String special**    | empty `""`, whitespace `" "`, multi-byte (emoji 🎉, Vietnamese tiếng việt)                           |
| **Numeric precision** | float decimals `0.1+0.2=0.3?`, IEEE 754 edge cases                                                   |
| **HTTP timeout**      | request 1ms, 1s, default-1, default, default+1                                                       |

## Checklist

```
☐ Mỗi numeric/string-length constraint có 6 test cases (MIN-1, MIN, MIN+1, MAX-1, MAX, MAX+1)
☐ Date/datetime boundaries: today, yesterday, far-future, far-past, ISO format edges
☐ Array length: empty [], 1 item, N-1, N, N+1
☐ String special: empty "", whitespace " ", multi-byte (emoji, Vietnamese)
☐ Expected status verified per case (200 / 400 / 422)
☐ Off-by-one bugs caught (MIN vs MIN+1 differentiation)
```

## See also

- [equivalence-partition.md](./equivalence-partition.md) — combine với BV (BV = đại diện boundary partition)
- [decision-table.md](./decision-table.md)
