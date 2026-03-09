# PTCAPS

R-based tools for analyzing Indiana's property tax system, with a focus on local government revenues and taxpayer bills.

## Background

Indiana's property tax system is administered at the local level under state rules set by the Department of Local Government Finance (DLGF). Each parcel's tax bill is the product of its net assessed value (after deductions and exemptions), the applicable local tax rate, and property tax caps (circuit breakers) that limit bills as a percentage of gross assessed value. Changes to any of these levers — deductions, rates, levies, or caps — ripple through to both individual taxpayer bills and aggregate local government revenues.

This project builds a reproducible, parcel-level baseline of Indiana property tax bills and a framework for simulating policy changes against that baseline.

## Data Sources

All data are sourced from DLGF and relate to pay year 2025 (assessment year 2024):

| File | Description |
|------|-------------|
| `TAXDATA_*.TXT` | Fixed-width parcel-level file with assessed values by cap bucket, net AV, local tax rate, gross tax, credits, and net tax due. Layout per 50 IAC 26. |
| `ADJMENTS_*.TXT` | Fixed-width parcel-level file with deductions, exemptions, and credits applied to each parcel. Layout per 50 IAC 26. |
| `2025_Certifed_Budget_Levy_CNAV_Rate_by_Fund.xlsx` | Certified levies, assessed values, and rates by taxing unit and fund. |
| `2025_Certifed_Tax_Rates_by_District_Unit.xlsx` | Tax rate crosswalk from tax district to taxing unit and fund. |
| `AdjustCodes.xlsx` | Code list for adjustment types (deductions, exemptions, credits) per PTMS Code List Manual, List 37. |
| `Fixed_Rate_Cap_Funds.xlsx` | Cumulative capital development funds assessed at fixed statutory rates. |
| `CapExemptFunds.xlsx` | Funds exempt from the property tax circuit-breaker cap (referendum funds). |

Raw data files are not tracked in this repository due to size. See `docs/` for layout references.

## Repository Structure

```
in_ptax/
├── R/                              # Core functions
│   ├── read_taxdata.R              # FWF reader for TAXDATA (readr; implied decimal scaling)
│   ├── read_adjust.R               # FWF reader for ADJMENTS (readr; implied decimal scaling)
│   ├── PTBill.R                    # Property tax bill calculation and cap application
│   ├── MaxTaxBill.R                # Maximum allowable bill under circuit-breaker caps
│   ├── sb1_supp.R                  # SB 1 (2025): homestead phase-in + LOIT credit elimination
│   ├── budget_tax_rates.R          # Fund classification for aggregate budget levy file
│   ├── district_tax_rates.R        # Fund classification for district/unit crosswalk
│   ├── district_rates.R            # District-level composite rates (aggregates crosswalk)
│   ├── netav_taxbill.R             # Parcel-level NetAV from TAXDATA + ADJMENTS
│   └── fiscal_analysis.R           # Workhorse simulation: bills, revenue allocation, unit summary
├── analysis/                       # Runnable scripts (baseline, validation, policy sims)
├── docs/                           # Reference documents and data layout notes
└── quality_reports/
    ├── plans/                      # Implementation plans and design notes
    └── session_logs/               # Lab journal and session notes
```

## Core Functions

### Data readers

- **`read_taxdata(file)`** — reads the TAXDATA fixed-width file using `readr::read_fwf`. Applies implied decimal scaling per 50 IAC 26: dollar-amount columns (Format 12.2) divided by 100; `LocalTaxRate` (Format 2.4) divided by 10,000 to yield $/100 AV.
- **`read_adjust(file)`** — reads the ADJMENTS fixed-width file. All four amount columns (Format 12.2) divided by 100 at import; returns dollars directly.

### Tax bill calculation

- **`PTBill(TAXDATA)`** — computes gross tax due, applies circuit-breaker cap, returns net tax and cap loss by parcel. Cap logic: `MaxTaxBill = 0.01 × Cap1AV + 0.02 × Cap2AV + 0.03 × Cap3AV`.
- **`MaxTaxBill(TAXDATA)`** — computes the maximum allowable bill for each parcel under the circuit-breaker caps.

### Rate pipeline

- **`budget_tax_rates(BUDGETDATA, FRF, CapExempt)`** — classifies each fund row in the aggregate budget levy file as fixed-rate vs. residual and cap-exempt vs. non-exempt; adds `FixedRate`, `ResidRate`, `ExemptRate`, `NonExemptRate` columns.
- **`district_tax_rates(xwalk, FRF, CapExempt)`** — same classification applied to the district/unit/fund crosswalk. Fund code column is `FUND_CD`; rate column is `CERTD_TAX_RATE_PCNT` ($/100 AV).
- **`district_rates(xwalk)`** — takes output of `district_tax_rates()` and sums the five rate columns across all unit×fund rows within each `CNTY_CD` + `TAX_DIST_CD`, yielding one composite rate row per tax district.

### Simulation pipeline

- **`netav_taxbill(TAXDATA, ADJMENTS)`** — computes parcel-level net assessed value from TAXDATA and ADJMENTS. Zeros circuit-breaker credits (AdjstCodes 61–63), aggregates type C credits, type D deductions, and type E exemptions by parcel. Returns `ParcelNum`, `StateDistrict`, `GrossAV`, `TotalCredits`, `TotalDeductions`, `TotalExemptions`, `NetAV` (= GrossAV − deductions − exemptions).
- **`fiscal_analysis(county, assessment_year, TAXDATA, ADJMENTS, BUDGETDATA, xwalk, FRF, CapExempt)`** — workhorse simulation function. Returns a named list with five outputs: `out.TAXDATA` (parcel-level bills including GrossTaxBill, NetBill, PTCLoss, SuppHTRC, ActualBill, and TIF bill split columns), `out.BUDGETDATA` (fund-level revenue allocation, using non-TIF bill totals), `out.LocalFisc` (unit-level Revenue and Unfunded summary), `out.TIFRevenue` (district-level TIF fund revenue with `UNIT_TYPE_CD = "99"` sentinel), and `out.UnitFund` (unit × fund baseline validation table). Use `county = 0` for all counties.

### Policy simulation

- **`sb1_supp(assessment_year, TAXDATA, ADJMENTS)`** — applies three SB 1 (2025) policy changes to ADJMENTS: (1) phases in a revised homestead deduction schedule for AdjstCodes "3" and "64" over 2025–2030+; (2) zeros out local income tax credits (AdjstCodes 57–60, 77–83) starting in assessment year 2027; (3) reclassifies AdjstCodes 4–10 from type "D" (deduction) to type "C" (credit) with fixed statutory amounts ($150 senior, $125 blind/disabled, $250 veteran with disability, $200 other veteran).

## Key Concepts

**TAXDATA fields:** Parcels carry assessed value broken out by cap bucket (Cap 1 = residential homestead, Cap 2 = other residential / agricultural / long-term care, Cap 3 = commercial / personal property). The property tax cap limits net tax to 1%, 2%, or 3% of gross AV for each bucket respectively.

**ADJMENTS records:** Each parcel may have multiple adjustment records. Adjustment type codes (C/E/D) and adjustment codes (List 37 in the PTMS manual) identify the specific deduction, exemption, or credit. The homestead standard deduction (AdjstCode "3") and supplemental deduction (AdjstCode "64") together define the homestead benefit.

**Tax districts:** A tax district is a unique combination of overlapping local governments within a county. Every parcel falls in exactly one tax district, and its `LocalTaxRate` equals the sum of all unit-fund rates for that district. `district_rates()` reconstructs this composite rate from the crosswalk.

**TIF increment AV:** `AV_TIF` in TAXDATA is the assessed value increment above the TIF base for parcels in a TIF district. This increment is excluded from the Certified Net Assessed Valuation (CNAV) used by taxing units for rate-setting — units set their levies against NAV net of TIF increment. However, taxpayers pay on the full `NetAV` (including TIF increment). The portion of each bill attributable to `AV_TIF / NetAV` flows to a TIF district fund and is reported in `out.TIFRevenue`; only the non-TIF portion flows to taxing unit revenues.

**Baseline validation:** Before running policy simulations, aggregate computed bills are reconciled against certified levy totals by county and taxing unit to confirm the pipeline is internally consistent.

## Reference

- 50 IAC 26 — DLGF administrative rule defining TAXDATA and ADJMENTS file layouts
- Property Tax Management System Code List Manual — defines all code lists referenced in TAXDATA and ADJMENTS
- IC 6-1.1 — Indiana Code governing property tax assessment, deductions, exemptions, and appeals
