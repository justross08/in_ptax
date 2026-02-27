# in_ptax

R-based tools for analyzing Indiana's property tax system, with a focus on local government revenues and taxpayer bills.

## Background

Indiana's property tax system is administered at the county level under state rules set by the Department of Local Government Finance (DLGF). Each parcel's tax bill is the product of its net assessed value (after deductions and exemptions), the applicable local tax rate, and property tax caps (circuit breakers) that limit bills as a percentage of gross assessed value. Changes to any of these levers — deductions, rates, levies, or caps — ripple through to both individual taxpayer bills and aggregate local government revenues.

This project builds a reproducible, parcel-level baseline of Indiana property tax bills and a framework for simulating policy changes against that baseline.

## Data Sources

All data are sourced from DLGF and relate to pay year 2025 (assessment year 2024):

| File | Description |
|------|-------------|
| `TAXDATA_*.TXT` | Fixed-width parcel-level file with assessed values by cap bucket, net AV, local tax rate, gross tax, credits, and net tax due. Layout per 50 IAC 26. |
| `ADJMENTS_*.TXT` | Fixed-width parcel-level file with deductions, exemptions, and credits applied to each parcel. Layout per 50 IAC 26. |
| `2025_Certifed_Budget_Levy_CNAV_Rate_by_Fund.xlsx` | Certified levies, assessed values, and rates by taxing unit and fund. |
| `2025_Certifed_Tax_Rates_by_District_Unit.xlsx` | Tax rate crosswalk from tax district to taxing unit. |
| `AdjustCodes.xlsx` | Code list for adjustment types (deductions, exemptions, credits) per PTMS Code List Manual, List 37. |
| `Fixed_Rate_Cap_Funds.xlsx` | Cumulative capital development funds assessed at fixed statutory rates. |

Raw data files are not tracked in this repository due to size. See `docs/` for layout references.

## Repository Structure

```
in_ptax/
├── R/                        # Core functions
│   ├── read_taxdata.R        # FWF reader for TAXDATA
│   ├── read_adjust.R         # FWF reader for ADJMENTS
│   └── pt_bill.R             # Property tax bill calculation and cap application
├── analysis/                 # Runnable scripts (baseline, validation, policy sims)
├── docs/                     # Reference documents and data layout notes
└── quality_reports/
    ├── plans/                # Implementation plans and design notes
    └── session_logs/         # Lab journal and session notes
```

## Key Concepts

**TAXDATA fields:** Parcels carry assessed value broken out by cap bucket (Cap 1 = residential homestead, Cap 2 = other residential / agricultural / long-term care, Cap 3 = commercial / personal property). The property tax cap limits net tax to 1%, 2%, or 3% of gross AV for each bucket respectively.

**ADJMENTS records:** Each parcel may have multiple adjustment records. Adjustment type codes (C/E/D) and adjustment codes (List 37 in the PTMS manual) identify the specific deduction, exemption, or credit. The homestead standard deduction (code 3) and supplemental deduction (code 4) together define the homestead benefit.

**Baseline validation:** Before running policy simulations, aggregate computed bills are reconciled against certified levy totals by county and taxing unit to confirm the pipeline is internally consistent.

## Reference

- 50 IAC 26 — DLGF administrative rule defining TAXDATA and ADJMENTS file layouts
- Property Tax Management System Code List Manual — defines all code lists referenced in TAXDATA and ADJMENTS
- IC 6-1.1 — Indiana Code governing property tax assessment, deductions, exemptions, and appeals
