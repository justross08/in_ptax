# Lab Journal — in_ptax

---

## 2026-02-27 — Session 1: Project inventory and setup

### Context

Starting the `in_ptax` repo to house reproducible R code for Indiana property tax analysis. The broader project lives in `PTCAPS/` (Dropbox), which also holds raw data and outputs that are too large to track in git.

### What exists

**Raw data (PTCAPS/data/):**
- `TAXDATA_ALLCOUNTIES_2024P2025.TXT` (~3 GB) and county-level Adams County subset — parcel-level FWF file per 50 IAC 26
- `ADJMENTS_ALLCOUNTIES_2024P2025.TXT` (~773 MB) and Adams County subset — parcel-level deductions/exemptions/credits
- `2025_Certifed_Budget_Levy_CNAV_Rate_by_Fund.xlsx` — certified levies by taxing unit and fund
- `2025_Certifed_Tax_Rates_by_District_Unit.xlsx` — tax rate crosswalk
- `AdjustCodes.xlsx` — PTMS List 37 adjustment codes
- `Fixed_Rate_Cap_Funds.xlsx` — fixed-rate cap fund list

**Reference docs (PTCAPS/docs/):**
- `50_IAC_26.pdf` — defines TAXDATA and ADJMENTS FWF layouts (pp. 93–97)
- `Property-Tax-Management-System-Code-List-Manual-231030.pdf` — PTMS code lists
- `260121-Culy-Memo-2026-Procedures-for-the-Establishment-of-Cumulative-Funds.pdf`

**Working R code (PTCAPS/code/):**
- `read_taxdata.R` — FWF reader, 49-column layout per 50 IAC 26
- `read_adjust.R` — FWF reader, 10-column layout per 50 IAC 26
- `PTBill.R` — computes gross tax, applies circuit-breaker caps, returns net tax and cap loss
- `SB1_2025.R` — standalone homestead deduction simulator for SB 51 (2025 session), not yet wired to parcel data
- `Test.R` — loads Adams County TAXDATA, ADJMENTS, levy data, and rate crosswalk together

### What the repo will hold

- `R/` — core functions (readers, bill calculator, eventually policy modules)
- `analysis/` — runnable scripts for baseline and simulations
- `docs/` — layout references and notes
- `quality_reports/` — this journal plus implementation plans

### Immediate next steps (not yet started)

1. Move core functions from `PTCAPS/code/` into `in_ptax/R/`
2. Build and validate a baseline pipeline on Adams County:
   - Read TAXDATA + ADJMENTS
   - Compute bills with PTBill logic
   - Reconcile aggregate net tax vs. certified levy totals
3. Document any discrepancies in this journal
4. Policy simulations deferred until baseline is validated

### Notes / open questions

- `PTBill.R` uses a row-wise `for` loop for cap application — will need vectorizing for statewide (~3M parcel) runs
- `read_taxdata.R` uses `read.fwf` which is slow for large files; may want to benchmark against `readr::read_fwf` on the statewide file
- Adams County (county code `01`) is the test bed throughout

---

## 2026-02-28 — Session 2: sb1_supp() function

### What was built

`sb1_supp.R` written to `PTCAPS/code/`. Function signature:

```r
sb1_supp(assessment_year, TAXDATA, ADJMENTS)
```

Returns a modified copy of ADJMENTS with `TotalAdjustAmount` updated for homestead deduction rows (`AdjstCode == "3"` and `AdjstCode == "64"`) to reflect the SB 1 (2025) phase-in schedule. All other rows are passed through unchanged.

### Design decisions

**Scope:** Only existing ADJMENTS rows are updated. No new rows are created. Parcels without existing AdjstCode "3" or "64" records are not affected (they are not currently homestead-eligible and SB 1 does not change that).

**GrossAV source:** Pulled from TAXDATA via parcel-level join on ParcelNum. Parcels present in ADJMENTS homestead rows but absent from TAXDATA produce a warning and are skipped.

**Storage units:** TotalAdjustAmount is stored as dollars × 100 per the FWF spec (e.g., $48,000 → 4800000). Output values are rounded to the nearest integer after conversion.

**75% statutory cap:** Total deduction (standard + supplemental combined) is capped at 75% of GrossAV. Supplemental is reduced first; standard is reduced only if standard alone exceeds 75% of GrossAV, which occurs only for very low-value parcels.

**Whitespace handling:** AdjstCode and ParcelNum are trimmed with `trimws()` before matching. `read.fwf` may pad fixed-width character fields.

**Year boundary:** assessment_year < 2025 returns ADJMENTS unchanged with a warning. assessment_year >= 2030 applies the 2030 schedule.

### Phase-in schedule implemented

| Year  | Std Cap  | Supp Rate |
|-------|----------|-----------|
| 2025  | $48,000  | 40%       |
| 2026  | $40,000  | 46%       |
| 2027  | $30,000  | 52%       |
| 2028  | $20,000  | 57%       |
| 2029  | $10,000  | 62%       |
| 2030+ | $0       | 66.7%     |

### Open questions / to validate

- ~~AdjstCode "4" confirmed as standard deduction~~ — **corrected**: AdjstCode "3" is the standard deduction; "4" was wrong. Consistent with the example in read_adjust.R and confirmed by user.
- Test.R updated to use `sb1_supp()` with corrected argument order `(assessment_year, TAXDATA, ADJMENTS)`.
- AdjstAmt1/2/3 sub-components are not updated, only TotalAdjustAmount. If downstream code relies on the components, those will need separate handling.

### Amendments to sb1_supp() — same session

Added LOIT credit elimination: for `assessment_year >= 2027`, `TotalAdjustAmount` is set to `0` for any row with AdjstCode in 57–60 or 77–83 (local income tax credits used for property tax replacement). Logic is independent of the homestead deduction join — it applies to all matching rows regardless of TAXDATA. NA fix also applied: GrossAV NAs are filtered out before deduction calculations, with a warning, preventing `any(over)` from receiving NA and erroring.

---

## 2026-02-28 — Session 3: Rewrote FWF readers

### Changes

Both `read_taxdata.R` and `read_adjust.R` rewritten to use `readr::read_fwf` in place of base R `read.fwf`.

**Why:** `read.fwf` internally converts the FWF file to CSV before parsing — extremely slow on large files (3 GB TAXDATA could take 30–60+ min). `readr::read_fwf` reads directly in C++ and is typically 20–50× faster.

**Column types now explicit:**
- TAXDATA: 17 character columns (ParcelNum, all address/name fields, TaxDistrict, StateDistrict, Township, School, Blind); remaining 32 as `col_double()`.
- ADJMENTS: 3 character columns (ParcelNum, AdjstTypeCode, AdjstCode); remaining 7 as `col_double()`.
- Key fix: TaxDistrict, Township, School, and AdjstCode were previously inferred as numeric, silently dropping leading zeros and breaking downstream joins and code matches.

**Whitespace:** `readr` trims character fields by default (`trim_ws = TRUE`). The defensive `trimws()` calls in `sb1_supp.R` are kept as a safety net but are no longer strictly necessary when using these readers.

**NA handling:** `na = c("", " ")` specified explicitly. Blank and whitespace-only fields return NA. Global NA → 0 replacement (the commented-out line in the old readers) is not applied; callers handle NAs explicitly.

**No functional changes to ADJMENTS or TAXDATA structure** — same column names, same widths, same skip = 1. Drop-in replacement.

---

## 2026-02-28 — Session 4: Implied decimal scaling in read_taxdata()

### Finding

50 IAC 26 specifies implied decimal formats for several TAXDATA columns. The raw file stores these as integers with no decimal point; the format notation indicates where the decimal belongs.

### Column scaling applied at import

| Format | Divisor | Columns |
|--------|---------|---------|
| 12.2 (dollar amounts) | ÷ 100 | `LatePPPenalty`, `UVPPRPenalty`, `PriorD`, `PriorPenalty`, `TotalBill`, `GrossTaxDue`, `LocalTaxRelief`, `PropertyTaxCap`, `NetTaxDue`, `OtherCharges`, `OverdueTaxes` |
| 2.4 (tax rate) | ÷ 10,000 | `LocalTaxRate` |
| None (plain integers) | — | All AV columns (`GrossAV`, `NetAV`, all cap-bucket AV fields) |

### LocalTaxRate interpretation

Raw example from spec: `012345` → implied `01.2345` → **1.2345 dollars per $100 AV** after ÷ 10,000. `PTBill.R` then divides by 100 to obtain the decimal multiplier (0.012345), which is correct.

### Implementation

Post-processing block added inside `read_taxdata()` after `readr::read_fwf`. Dollar columns divided by 100 via vectorised assignment on the tibble; `LocalTaxRate` divided by 10,000 separately. No changes to column names or structure — fully compatible with existing downstream code.

---

## 2026-02-28 — Session 5: Implied decimal scaling in read_adjust(); sb1_supp() fix

### Finding

50 IAC 26 pp. 96-97 shows all four ADJMENTS amount columns use Format 12.2 (implied 2 decimal places). `StartYear` is type A in the spec (character), not numeric.

### Column scaling applied at import

| Format | Divisor | Columns |
|--------|---------|---------|
| 12.2 (dollar amounts) | ÷ 100 | `TotalAdjustAmount`, `AdjstAmt1`, `AdjstAmt2`, `AdjstAmt3` |
| None | — | `AdjustInstNum`, `NumYears` |

`StartYear` corrected from `col_double()` to `col_character()`.

### Cascade fix: sb1_supp.R

`sb1_supp()` previously multiplied computed deductions by 100 before writing back to `TotalAdjustAmount`, assuming raw storage units. Since `read_adjust()` now returns dollars directly, the ×100 conversion was removed:
- `round(new_std * 100)` → `round(new_std, 2)`
- `round(new_supp * 100)` → `round(new_supp, 2)`
- LOIT zero-out changed from `0L` to `0` for type consistency.

Header note in `sb1_supp.R` updated to reflect that `TotalAdjustAmount` is in dollars at runtime.

---

## 2026-02-28 — Session 6: budget_tax_rates()

### What was built

`budget_tax_rates.R` written to `PTCAPS/code/`. Function signature:

```r
budget_tax_rates(BUDGETDATA, FRF, CapExempt)
```

### Source column names confirmed from actual files

| Input | Fund code column | Rate column |
|-------|-----------------|-------------|
| BUDGETDATA | `Fund` (4-char, zero-padded) | `Certified Gross Tax Rate` |
| FRF | `Fund` (same format) | — |
| CapExempt | `Fund Code` (space in name) | — |

`Certified Gross Tax Rate` is already in $/100 AV format in the Excel file (no scaling needed).

### Columns added to BUDGETDATA

| Column | Definition |
|--------|-----------|
| `RateFund` | 1 if `Fund` ∈ FRF; else 0 |
| `ResidFund` | 1 − RateFund |
| `ExemptFund` | 1 if `Fund` ∈ CapExempt; else 0 |
| `NonExemptFund` | 1 − ExemptFund |
| `FixedRate` | `Certified Gross Tax Rate` × RateFund |
| `ResidRate` | `Certified Gross Tax Rate` × ResidFund |
| `ExemptRate` | `Certified Gross Tax Rate` × ExemptFund — portion of rate not subject to circuit-breaker cap |
| `NonExemptRate` | `Certified Gross Tax Rate` × NonExemptFund — portion of rate subject to capping |

### Design notes

- Matching is exact string comparison on the 4-char zero-padded fund code — no trimming needed as Excel import preserves format
- CapExemptFunds.xlsx contains more funds than the CLAUDE.md shortlist; several are marked "Do Not Use 2021 Budget Onward" — caller should pre-filter CapExempt if only active-post-2021 exempt funds are wanted

---

## 2026-02-28 — Session 7: district_tax_rates()

### What was built

`district_tax_rates.R` written to `PTCAPS/code/`. Function signature:

```r
district_tax_rates(xwalk, FRF, CapExempt)
```

Crosswalk-level analogue of `budget_tax_rates()`. Applies identical fund classification logic and produces the same eight derived columns, but operates on the district/unit/fund crosswalk (`xwalk`) from `2025_Certifed_Tax_Rates_by_District_Unit.xlsx`.

### Source column names confirmed from actual file

| Input | Fund code column | Rate column |
|-------|-----------------|-------------|
| xwalk | `FUND_CD` (4-char, zero-padded) | `CERTD_TAX_RATE_PCNT` |
| FRF | `Fund` (same format) | — |
| CapExempt | `Fund Code` (space in name) | — |

`CERTD_TAX_RATE_PCNT` is already in $/100 AV (no implied-decimal scaling needed). Range confirmed 0–3.96 in Adams County data. `FUND_CD` is 4-char zero-padded — matches FRF and CapExempt fund code formats directly.

Other xwalk columns: `YR_NBR`, `CNTY_CD`, `UNIT_TYPE_CD`, `UNIT_CD`, `UNIT_NAME`, `FUND_LONG_NAME`, `TAX_DIST_CD`, `TAX_DIST_NAME`. All retained in output alongside the eight new columns.

### Columns added to xwalk

| Column | Definition |
|--------|-----------|
| `RateFund` | 1 if `FUND_CD` ∈ FRF; else 0 |
| `ResidFund` | 1 − RateFund |
| `ExemptFund` | 1 if `FUND_CD` ∈ CapExempt; else 0 |
| `NonExemptFund` | 1 − ExemptFund |
| `FixedRate` | `CERTD_TAX_RATE_PCNT` × RateFund |
| `ResidRate` | `CERTD_TAX_RATE_PCNT` × ResidFund |
| `ExemptRate` | `CERTD_TAX_RATE_PCNT` × ExemptFund |
| `NonExemptRate` | `CERTD_TAX_RATE_PCNT` × NonExemptFund |

---

## 2026-02-28 — Session 8: district_rates()

### What was built

`district_rates.R` written to `PTCAPS/code/`. Function signature:

```r
district_rates(xwalk)
```

Takes the output of `district_tax_rates()` (the crosswalk with the five rate columns already populated) and aggregates to one row per tax district by summing all unit×fund rate rows within each `CNTY_CD` + `TAX_DIST_CD` combination.

### Crosswalk structure confirmed (Adams County)

- 529 rows total; 23 unique tax districts, 22 units, 27 funds
- Each row is one district × unit × fund combination
- `TAX_DIST_NAME` is 1:1 with `CNTY_CD` + `TAX_DIST_CD` — carried through as a label column
- Example: district "001" has 20 unit×fund rows summing to 1.6764 $/100 AV

### Design

- `aggregate()` with `FUN = sum, na.rm = TRUE` over the five rate columns
- By-group: `CNTY_CD`, `TAX_DIST_CD`, `TAX_DIST_NAME` (TAX_DIST_NAME included since it is 1:1 and useful for joins/display)
- Output sorted by `CNTY_CD` then `TAX_DIST_CD`
- The `CERTD_TAX_RATE_PCNT` total in the output should equal `LocalTaxRate` in TAXDATA (after the 2.4-format implied decimal is applied at import) for parcels in the same district

---

## 2026-03-01 — Session 9: First push to GitHub

### Actions

- Copied all working R functions from `PTCAPS/code/` to `in_ptax/R/`:
  `read_taxdata.R`, `read_adjust.R`, `PTBill.R`, `MaxTaxBill.R`, `sb1_supp.R`,
  `budget_tax_rates.R`, `district_tax_rates.R`, `district_rates.R`
- README.md updated and synced to `in_ptax/README.md`:
  - Fixed incorrect AdjstCode reference ("4" → "64" for supplemental deduction)
  - Added `CapExemptFunds.xlsx` to data sources table
  - Updated R/ directory listing and added full function inventory
  - Added Tax districts concept explanation
- CLAUDE.md status section updated to reflect current state
- Committed and pushed to `origin/main`

---

## 2026-03-01 — Session 10: netav_taxbill()

### What was built

`netav_taxbill.R` written to `PTCAPS/code/`. Function signature:

```r
netav_taxbill(TAXDATA, ADJMENTS)
```

Returns a parcel-level data frame (`NETAV`) with one row per parcel in TAXDATA containing GrossAV, aggregated credits and deductions from ADJMENTS, and computed NetAV.

### Design decisions

**Circuit-breaker credits zeroed before aggregation:** AdjstCodes "61", "62", "63" are set to zero before the credit aggregation step. These are cap credits that the downstream cap-application functions will recalculate; including the existing values would double-count them.

**AdjstTypeCode "E" (exemptions) excluded:** Exemptions reduce assessed value through a separate administrative process and are not summed into TotalCredits or TotalDeductions. Only types "C" and "D" are aggregated.

**TAXDATA as parcel universe:** Left-join from TAXDATA — parcels in ADJMENTS but absent from TAXDATA are dropped. Parcels in TAXDATA with no ADJMENTS rows receive TotalCredits = 0 and TotalDeductions = 0.

**NetAV = GrossAV − TotalDeductions.** Credits do not reduce AV; they reduce the tax bill directly and are carried forward for use in the bill calculation step.

### Output columns

| Column | Definition |
|--------|-----------|
| `ParcelNum` | Parcel identifier (from TAXDATA) |
| `GrossAV` | Gross assessed value |
| `TotalCredits` | Sum of non-circuit-breaker credit amounts (AdjstTypeCode "C", excl. codes 61–63) |
| `TotalDeductions` | Sum of deduction amounts (AdjstTypeCode "D") |
| `NetAV` | GrossAV − TotalDeductions |

### Amendment: exemptions added to NetAV calculation

Initial implementation only subtracted deductions (type "D") from GrossAV. Validation against TAXDATA revealed 563 mismatching parcels and a $91.4M aggregate gap. Diagnosis: all 818 exemption rows (AdjstTypeCode "E") in Adams County belong to those 563 parcels, and their TotalAdjustAmount sums to exactly the gap. Exemptions reduce assessed value in the same way as deductions and must be included.

**Fix applied:** Added `TotalExemptions` column (type "E" aggregate) and updated:
- `NetAV = GrossAV − TotalDeductions − TotalExemptions`

### Validation on Adams County (post-fix)

- 23,140 parcels; exact NetAV match on all 23,139 non-NA parcels
- 0 mismatches; aggregate totals identical: sum(GrossAV) = $3.31B, sum(NetAV) = $2.14B
- 1 parcel with NA GrossAV in TAXDATA — NetAV also NA, expected

### Output columns (final)

| Column | Definition |
|--------|-----------|
| `ParcelNum` | Parcel identifier (from TAXDATA) |
| `StateDistrict` | State tax district code; identifies the county |
| `GrossAV` | Gross assessed value |
| `TotalCredits` | Sum of type "C" adjustments, excluding circuit-breaker codes 61–63 |
| `TotalDeductions` | Sum of type "D" adjustments |
| `TotalExemptions` | Sum of type "E" adjustments |
| `NetAV` | GrossAV − TotalDeductions − TotalExemptions |

---

## 2026-03-01 — Session 11: fiscal_analysis()

### What was built

`fiscal_analysis.R` written to `PTCAPS/code/`. Function signature:

```r
fiscal_analysis(county, assessment_year, TAXDATA, ADJMENTS,
                BUDGETDATA, xwalk, FRF, CapExempt)
```

Returns a named list with three output data frames.

### Inputs

| Argument | Description |
|----------|-------------|
| `county` | County code (integer or character; "01" or 1 for Adams; 0 = all) |
| `assessment_year` | Assessment year (pay year − 1); governs SuppHTRC |
| `TAXDATA` | From read_taxdata() |
| `ADJMENTS` | From read_adjust() |
| `BUDGETDATA` | From read_excel() on budget levy file |
| `xwalk` | From read_excel() on rate crosswalk |
| `FRF` | Fixed-rate fund list |
| `CapExempt` | Cap-exempt fund list (caller pre-filters to active post-2021 funds) |

Note: `FRF` and `CapExempt` are required arguments not listed in the original spec; they are needed by `budget_tax_rates()` and `district_tax_rates()`.

### Outputs

| Name | Level | Key columns |
|------|-------|-------------|
| `out.TAXDATA` | Parcel | All TAXDATA fields + NetAV, MaxTaxBill, GrossTaxBill, NonExemptGrossBill, ExemptGrossBill, NetBill, PTCLoss, SuppHTRC, ActualNonExemptBill, ActualBill |
| `out.BUDGETDATA` | District × unit × fund | Recalculated Certified Levy, rate components, sum_ bill aggregates, shr_ rate shares, Revenue, Unfunded |
| `out.LocalFisc` | County × unit | Revenue, Unfunded |

### Pipeline (9 steps)

1. **netav_taxbill** → NETAV (parcel NetAV and adjustment totals)
2. **district_tax_rates** → DISTRICTRATES_f (xwalk with fund flags and FixedRate; drop CERTD_TAX_RATE_PCNT, ResidRate, ExemptRate, NonExemptRate)
3. Aggregate NETAV by StateDistrict → aggNV ("Certified Net Assessed Valuation")
4. Merge aggNV onto DISTRICTRATES_f by TAX_DIST_CD → NewAV_by_fund
5. **budget_tax_rates** → BUDGETRATES; add OtherRev, ResidLevy; drop rate/classification columns → BUDGETDATA2
6. Merge NewAV_by_fund onto BUDGETDATA2 (by CNTY_CD/County, UNIT_CD/Unit Code, FUND_CD/Fund) → LocalFisc_Fund; recalculate Certified Levy, ResidRate, ExemptRate, NonExemptRate, CGR from new NAV
7. Build TAXDATA2; merge NETAV columns and MaxTaxBill; join district composite rates; compute 8 bill variables → out.TAXDATA + aggTaxBills (sum. prefix)
8. Aggregate rates by TAX_DIST_CD + ExemptFund (sum_ prefix); merge back; compute shr_ shares → LocalFisc_Fund2
9. Merge aggTaxBills onto LocalFisc_Fund2; compute Revenue and Unfunded → out.BUDGETDATA; aggregate by CNTY_CD + UNIT_CD → out.LocalFisc

### Key design notes

**Column name mismatch at step 6 merge:** BUDGETDATA uses `County`, `Unit Code`, `Fund`; xwalk uses `CNTY_CD`, `UNIT_CD`, `FUND_CD`. Handled via by.x/by.y in merge(). Result keeps xwalk column names.

**Certified Gross Tax Rate formula:** CGR = ResidRate + FixedRate. ResidFund and RateFund are mutually exclusive (ResidFund = 1 − RateFund), so exactly one term is non-zero per fund and the sum equals the total fund rate without double-counting. ExemptRate and NonExemptRate partition this total for cap analysis and revenue allocation but are not included in CGR.

**SuppHTRC:** pmax(300, 0.10 × NetBill) applied to all parcels when assessment_year ≥ 2025. No homestead filter in spec; applied universally as written.

**NAV = 0 guard:** safe_rate = 0 when NAV is 0 or NA to prevent Inf/NaN in rate calculations.
