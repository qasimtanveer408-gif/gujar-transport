# Remaining decisions and dependencies

Independent repairs are implemented. These focused business decisions remain unresolved after inspecting the source and images:

1. **company**: should the one field represent the existing manufacturer or the distinct fleet owner company? The UI explicitly flags the provisional manufacturer mapping; ownership data is preserved.
2. **pp / punjab police**: confirm that the existing documented fines/permit-fees category is the intended scope. No payment purpose was invented.
3. **Printed monthly and settlement values**: define INCOME, Total Sale, Driver Sale, Last Main, Total Main, MAIN and MIST, including which values are current costs versus carried balances. Provide verified sources for tracker, vehicle/salary advances, absence/call/vehicle-loss/other deductions, period loan installments and net-payable rules. These cells remain blank and reports remain INCOMPLETE.
4. **Shares/comparisons**: provide the approved percentage, share count, beneficiary allocations and historical comparison records. None of the photographed personal values were copied.
5. **Office contact and reference additions**: confirm driver_contact always contains a mobile number and identify any separate external-driver-name source. Confirm an exact printed position before adding handwritten weight/cycle annotations to the cycle sheet; both already appear in full-field exports.

Operational dependencies: review the two migrations against staging; validate hosted authorization and hosting; review XLSX printing in your native Excel version. No live action is required merely to inspect the included test PDFs, workbooks and screenshots.
