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
