# Common — Equivalence Partitioning (Phân vùng tương đương)

Áp dụng cho **cả API + E2E**. Chia input space thành **partitions** — mỗi partition test 1 representative, giả định BE behavior identical trong partition.

## Phương pháp

1. Identify input field + constraints.
2. Chia space thành **valid partitions** (input phù hợp) và **invalid partitions** (rejected).
3. Pick 1 đại diện per partition.
4. **Boundary** tách riêng — xem [boundary-value.md](./boundary-value.md).

## Template

| Field                    | Valid partitions                           | Invalid partitions                                                                |
| ------------------------ | ------------------------------------------ | --------------------------------------------------------------------------------- |
| `email`                  | `valid@x.com`, `user.name+tag@sub.x.co.uk` | `@x.com` · `invalid` · `x@` · `@` · `null`                                        |
| `Platform`               | `YOUTUBE`, `INSTAGRAM`, `X`                | `TWITTER` (legacy) · `youtube` (case) · `LINKEDIN` (unsupported) · `null` · `123` |
| `TacticType`             | `landing_page`, `youtube_poll`             | `unknown_tactic` · empty string · `null` · array `[…]`                            |
| `campaignId`             | valid UUID v7                              | UUID v4 · empty · `null` · `not-a-uuid` · SQL injection string                    |
| `durationDays`           | 3, 7, 14                                   | `0` · negative · float `7.5` · string `"7"` · `null`                              |
| `pollUrl` (YouTube poll) | `https://youtube.com/...`                  | non-YouTube domain · `not-a-url` · `javascript:...` · empty                       |

## Khi nào split partition?

Split khi BE behavior khác:

- Status code khác (200 vs 400)
- Validation message khác
- Side effect khác (vd email sent vs not sent)

Cùng partition khi BE treat identical → đại diện 1 case là đủ.

## Combined partition (multi-field)

Khi 2+ field tương tác → cartesian product of partitions (xem [decision-table.md](./decision-table.md) cho format).

Ví dụ login:
| email partition | password partition | Expected |
|---|---|---|
| valid registered | valid | 200 OK |
| valid registered | wrong | 401 |
| valid unregistered | _ | 401 |
| invalid format | _ | 400 |

## Checklist

```
☐ Mỗi field có ít nhất 1 valid partition test
☐ Mỗi invalid category có 1 negative test (rejected format, wrong type, null, out-of-enum)
☐ Boundary cases tách riêng (xem boundary-value.md)
☐ Multi-field combined partitions cover qua decision table khi cần
☐ Status code expected + error message verified per partition
```

## See also

- [boundary-value.md](./boundary-value.md) — BV phủ partition edges
- [decision-table.md](./decision-table.md) — multi-condition logic
