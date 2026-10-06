# Accounting rules

Operating Profit = recognized revenue minus recognized operating expenses. No depreciation, statutory tax or ownership-distribution rule is inferred.

Fare posts once on trip approval. Draft/submitted/rejected trips do not recognize revenue. Itemized lines and maintenance invoice items have distinct unique source postings. Never manually duplicate an invoice across screens. Trip/office-expense voiding writes linked negative reversal entries; posted records cannot be overwritten. Paid source restrictions require a reviewed correction. Commission earnings remain historically visible as Voided when applicable.

External booking freight is descriptive; only commission is your revenue. A booking linked to an owned trip requires zero separate commission. Driver earning accrual posts an expense; allocating a payment to it posts cash only. Loan principal/disbursements/repayments are not operating profit. Opening principal creates neither new cash nor expense. Over-repayment and overpayment are rejected.

Money is NUMERIC(18,2) and serialized as decimal strings. Decimal.js uses 32-digit precision and half-up rounding; physical measures display three decimals and efficiency two. Chart coordinates are drawing values, not accounting calculations.

| Example | Result |
|---|---|
| Fare 80,000; costs 29,000 + 3,000 + 1,200 + 2,000 + 800 | Expenses 36,000; profit 44,000 PKR |
| Odometers 144,844 → 145,382 | 538 km |
| 538 / 68 litres | 7.91 km/L |
| Zero/missing litres | Not available |
| Aggregate fuel | Sum matched km / sum matching litres, same basis |

Closed periods block financial changes under the same lock used by posting. Reopen requires a reason and preserves original close snapshots. Unallocated overhead appears separately in vehicle ranking and within company totals. Purchase-based fuel is labelled estimated.

Pending: percentage commission, payroll deductions/advances/recovery, loan/payment reversals, receivable/payable cash allocation entry, approved adjustments/odometer replacement, historical balances and complete reconciliation. Do not imitate these by editing ledger balances or duplicate expense entry.
