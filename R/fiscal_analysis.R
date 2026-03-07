# fiscal_analysis.R
#
# Workhorse simulation function. Takes a baseline set of parcel, budget, and
# crosswalk inputs, applies the current SB1/policy rules, and returns three
# output data frames: parcel-level tax bills (out.TAXDATA), fund-level fiscal
# results with revenue allocation (out.BUDGETDATA), and unit-level fiscal
# summary (out.LocalFisc).
#
# INPUTS
#   county         County code to process. Use 0 for all counties. Integer or
#                  character (both "1" and "01" are accepted for Adams County).
#   assessment_year  Assessment year (pay year - 1). Governs SuppHTRC
#                  eligibility (>= 2025).
#   TAXDATA        Data frame from read_taxdata().
#   ADJMENTS       Data frame from read_adjust().
#   BUDGETDATA     Data frame from read_excel() on
#                    2025_Certifed_Budget_Levy_CNAV_Rate_by_Fund.xlsx.
#                  Key columns: County, Unit Code, Fund,
#                    Certified Budget, Certified Levy,
#                    Certified Net Assessed Valuation, Certified Gross Tax Rate.
#   xwalk          Data frame from read_excel() on
#                    2025_Certifed_Tax_Rates_by_District_Unit.xlsx.
#                  Key columns: CNTY_CD, TAX_DIST_CD, UNIT_CD, FUND_CD,
#                    CERTD_TAX_RATE_PCNT.
#   FRF            Data frame from read_excel() on Fixed_Rate_Cap_Funds.xlsx.
#                  Key column: Fund — fixed-rate cumulative capital fund codes.
#   CapExempt      Data frame from read_excel() on CapExemptFunds.xlsx.
#                  Key column: `Fund Code` — circuit-breaker cap exempt fund
#                  codes. Caller should pre-filter to active (post-2021) funds.
#
# OUTPUTS  (returned as a named list)
#   out.TAXDATA    Parcel-level data frame. Contains all original TAXDATA
#                  columns (minus cleared bill fields), computed NetAV,
#                  deduction/credit/exemption totals, MaxTaxBill, and new
#                  bill variables: GrossTaxBill, NonExemptGrossBill,
#                  ExemptGrossBill, NetBill, PTCLoss, SuppHTRC,
#                  ActualNonExemptBill, ActualBill.
#   out.BUDGETDATA District × unit × fund level data frame. Contains fund
#                  classification flags, recalculated levies and rates based
#                  on new NAV, district bill aggregates, fund revenue shares,
#                  Revenue, and Unfunded (for non-exempt funds only).
#   out.LocalFisc  Unit-level summary: CNTY_CD, UNIT_TYPE_CD, UNIT_CD,
#                  Revenue, Unfunded.
#   out.UnitFund   Unit × fund validation table. One row per
#                  CNTY_CD × UNIT_TYPE_CD × UNIT_CD × FUND_CD. Contains
#                  computed values (Comp_CNAV, Comp_CGR, Comp_Levy,
#                  Comp_Revenue, Comp_Unfunded) alongside the submitted
#                  input values (Sub_CNAV, Sub_CGR, Sub_Levy) for
#                  side-by-side comparison. Also carries UNIT_NAME and
#                  FUND_LONG_NAME from the crosswalk for readability.
#
# HELPER FUNCTIONS USED
#   netav_taxbill, budget_tax_rates, district_tax_rates, MaxTaxBill
#
# NOTES
#   - County filter is applied to all four input files at entry using the
#     first 2 characters of ParcelNum (parcel files) and CNTY_CD / County
#     columns (xwalk / BUDGETDATA).
#   - Certified Gross Tax Rate in LocalFisc_Fund is computed as
#     ResidRate + FixedRate. ResidFund and RateFund are mutually exclusive
#     (ResidFund = 1 - RateFund), so exactly one term is non-zero per fund
#     and the sum equals the total fund rate with no double-counting.
#     ExemptRate and NonExemptRate partition this total for cap analysis
#     and revenue allocation but are not included in CGR.
#   - District-level composite rates for parcel billing are obtained by
#     summing fund-level rates within each TAX_DIST_CD from LocalFisc_Fund.
#   - SuppHTRC = max($300, 10% of NetBill) when assessment_year >= 2025,
#     applied to all parcels as specified. Zero otherwise.

fiscal_analysis <- function(county, assessment_year,
                            TAXDATA, ADJMENTS, BUDGETDATA, xwalk,
                            FRF, CapExempt) {

  # ── County filter ──────────────────────────────────────────────────────────
  # county = 0  →  all counties; else restrict all inputs to that county.
  # County code in parcel files = first 2 chars of ParcelNum (zero-padded).
  if (as.integer(county) != 0) {
    cty_cd   <- sprintf("%02d", as.integer(county))
    TAXDATA  <- TAXDATA[substr(trimws(TAXDATA$ParcelNum),   1, 2) == cty_cd, ]
    ADJMENTS <- ADJMENTS[substr(trimws(ADJMENTS$ParcelNum), 1, 2) == cty_cd, ]
    BUDGETDATA <- BUDGETDATA[BUDGETDATA$County == cty_cd, ]
    xwalk    <- xwalk[xwalk$CNTY_CD == cty_cd, ]
  }

  # ── Step 1: NETAV ──────────────────────────────────────────────────────────
  # ParcelNum, StateDistrict, GrossAV, TotalCredits, TotalDeductions,
  # TotalExemptions, NetAV
  NETAV <- netav_taxbill(TAXDATA, ADJMENTS)

  # ── Step 2: DISTRICTRATES_f ────────────────────────────────────────────────
  # Process xwalk with district_tax_rates; drop rate columns that will be
  # recalculated from new NAV in step 6. Keep fund classification flags and
  # FixedRate (statutory; does not change with NAV).
  DISTRICTRATES_f <- district_tax_rates(xwalk, FRF, CapExempt)
  drop_drf <- c("CERTD_TAX_RATE_PCNT", "ResidRate", "ExemptRate", "NonExemptRate")
  DISTRICTRATES_f <- DISTRICTRATES_f[, !names(DISTRICTRATES_f) %in% drop_drf]

  # ── Step 3: unit_NAV ───────────────────────────────────────────────────────
  # Sum parcel NetAV to the unit level. Each parcel belongs to one district;
  # each district overlaps multiple units. Expand via the xwalk (deduplicated
  # to district × unit) to assign parcels to their units, then aggregate by
  # CNTY_CD + UNIT_TYPE_CD + UNIT_CD. This is the correct denominator for the
  # rate formula (levy / unit_NAV), since certified levies in BUDGETDATA are
  # unit-totals, not district-level amounts.
  dist_unit_map <- unique(xwalk[, c("CNTY_CD", "UNIT_TYPE_CD", "TAX_DIST_CD", "UNIT_CD")])
  netav_by_unit <- merge(
    NETAV[, c("StateDistrict", "NetAV")],
    dist_unit_map,
    by.x = "StateDistrict", by.y = "TAX_DIST_CD",
    all.x = FALSE
  )
  unit_NAV <- aggregate(NetAV ~ CNTY_CD + UNIT_TYPE_CD + UNIT_CD,
                        data = netav_by_unit, FUN = sum, na.rm = TRUE)
  names(unit_NAV)[names(unit_NAV) == "NetAV"] <- "Certified Net Assessed Valuation"

  # ── Step 4: NewAV_by_fund ──────────────────────────────────────────────────
  # Attach new unit-level NAV to every district × unit × fund row in the
  # crosswalk. Merge key is CNTY_CD + UNIT_TYPE_CD + UNIT_CD; TAX_DIST_CD is
  # already in DISTRICTRATES_f and is preserved in the output.
  # Result has one row per TAX_DIST_CD × UNIT_TYPE_CD × UNIT_CD × FUND_CD.
  NewAV_by_fund <- merge(
    DISTRICTRATES_f, unit_NAV,
    by  = c("CNTY_CD", "UNIT_TYPE_CD", "UNIT_CD"),
    all.x = TRUE
  )

  # ── Step 5: BUDGETDATA2 ────────────────────────────────────────────────────
  # Classify BUDGETDATA funds, derive ancillary levy variables, and drop
  # columns that will be reconstructed from new NAV in step 6.
  BUDGETRATES <- budget_tax_rates(BUDGETDATA, FRF, CapExempt)

  BUDGETRATES$OtherRev  <- BUDGETRATES$`Certified Budget` - BUDGETRATES$`Certified Levy`
  BUDGETRATES$ResidLevy <- BUDGETRATES$`Certified Levy`   * BUDGETRATES$ResidFund

  # Drop rate/valuation columns (to be reconstructed) and classification
  # columns (identical to xwalk versions; will come from NewAV_by_fund).
  drop_bgt <- c("Certified Net Assessed Valuation", "Certified Gross Tax Rate",
                "ResidRate", "ExemptRate", "NonExemptRate", "Certified Budget",
                "RateFund", "ResidFund", "ExemptFund", "NonExemptFund", "FixedRate")
  BUDGETDATA2 <- BUDGETRATES[, !names(BUDGETRATES) %in% drop_bgt]

  # ── Step 6: LocalFisc_Fund ─────────────────────────────────────────────────
  # Merge unit NAV and fund classifications onto budget levy data.
  # NewAV_by_fund uses (CNTY_CD, UNIT_TYPE_CD, UNIT_CD, FUND_CD); BUDGETDATA2
  # uses (County, "Unit Type Code", "Unit Code", Fund) for the same concepts.
  # UNIT_TYPE_CD is required to uniquely identify units within a county
  # (UNIT_CD alone is not unique across unit types).
  # Result: one row per TAX_DIST_CD × unit type × unit × fund.
  LocalFisc_Fund <- merge(
    NewAV_by_fund, BUDGETDATA2,
    by.x = c("CNTY_CD", "UNIT_TYPE_CD", "UNIT_CD", "FUND_CD"),
    by.y = c("County",  "Unit Type Code", "Unit Code", "Fund"),
    all.x = FALSE, all.y = FALSE
  )

  # Recalculate Certified Levy under new NAV:
  #   ResidFund = 1 → levy is fixed by budget; rate adjusts to new NAV
  #   RateFund  = 1 → rate is fixed by statute; levy adjusts to new NAV
  NAV   <- LocalFisc_Fund$`Certified Net Assessed Valuation`
  LocalFisc_Fund$`Certified Levy` <- ifelse(
    LocalFisc_Fund$ResidFund == 1,
    LocalFisc_Fund$ResidLevy,
    NAV * LocalFisc_Fund$FixedRate / 100
  )

  # Recalculate rates ($/100 AV) from new levy and new NAV.
  # Guard against NAV = 0 or NA.
  # Round to 4 decimal places ($/100 AV percent form) before any downstream
  # use — bill calculation, rate component assignment, and district-level
  # summation all use the rounded value.
  levy      <- LocalFisc_Fund$`Certified Levy`
  safe_rate <- ifelse(!is.na(NAV) & NAV > 0, levy / NAV * 100, 0)
  safe_rate <- round(safe_rate, 4)

  LocalFisc_Fund$ResidRate     <- safe_rate * LocalFisc_Fund$ResidFund
  LocalFisc_Fund$ExemptRate    <- safe_rate * LocalFisc_Fund$ExemptFund
  LocalFisc_Fund$NonExemptRate <- safe_rate * LocalFisc_Fund$NonExemptFund

  # Certified Gross Tax Rate: sum of levy-based rate and fixed-rate components.
  # ResidRate and FixedRate are mutually exclusive (ResidFund = 1 - RateFund),
  # so this equals the total fund rate without double-counting.
  # ExemptRate and NonExemptRate are sub-partitions of this total used for
  # cap analysis and revenue allocation; they are not added here.
  LocalFisc_Fund$`Certified Gross Tax Rate` <-
    LocalFisc_Fund$ResidRate + LocalFisc_Fund$FixedRate

  # ── Step 7: TAXDATA2 with parcel-level bill variables ─────────────────────

  # Drop bill-related columns that will be replaced with computed values.
  drop_td <- c("TotalBill", "TotalAV", "NetAV", "GrossTaxDue",
               "LocalTaxRelief", "PropertyTaxCap", "NetTaxDue",
               "OtherCharges", "OverdueTaxes")
  TAXDATA2 <- TAXDATA[, !names(TAXDATA) %in% drop_td]

  # Merge computed NetAV and adjustment totals from NETAV.
  # Drop StateDistrict from NETAV (already present in TAXDATA2 from TAXDATA).
  netav_cols <- c("ParcelNum", "TotalCredits", "TotalDeductions",
                  "TotalExemptions", "NetAV")
  TAXDATA2 <- merge(TAXDATA2, NETAV[, netav_cols], by = "ParcelNum", all.x = TRUE)

  # MaxTaxBill: circuit-breaker cap maximum (from AV cap-bucket columns)
  mtb <- MaxTaxBill(TAXDATA2)
  TAXDATA2 <- merge(TAXDATA2, mtb, by = "ParcelNum", all.x = TRUE)

  # District-level composite rates for parcel billing.
  # Sum fund-level rates within each district to get the total district rate.
  rate_cols_lf <- c("Certified Gross Tax Rate", "NonExemptRate", "ExemptRate")
  dist_comp <- aggregate(
    LocalFisc_Fund[, rate_cols_lf],
    by  = list(StateDistrict = LocalFisc_Fund$TAX_DIST_CD),
    FUN = sum, na.rm = TRUE
  )
  TAXDATA2 <- merge(TAXDATA2, dist_comp, by = "StateDistrict", all.x = TRUE)

  # Bill variables. Rates are in $/100 AV → divide by 100 for decimal multiplier.
  TAXDATA2$GrossTaxBill       <- TAXDATA2$`Certified Gross Tax Rate` * TAXDATA2$NetAV / 100
  TAXDATA2$NonExemptGrossBill <- TAXDATA2$NonExemptRate              * TAXDATA2$NetAV / 100
  TAXDATA2$ExemptGrossBill    <- TAXDATA2$ExemptRate                 * TAXDATA2$NetAV / 100

  # Cap: net bill is the lesser of the non-exempt gross bill and the cap maximum.
  TAXDATA2$NetBill  <- pmin(TAXDATA2$NonExemptGrossBill, TAXDATA2$MaxTaxBill)
  TAXDATA2$PTCLoss  <- TAXDATA2$NonExemptGrossBill - TAXDATA2$NetBill

  # Supplemental Homestead Tax Relief Credit (SB1 2025+):
  # credit = max($300, 10% of NetBill)
  if (as.integer(assessment_year) >= 2025) {
    TAXDATA2$SuppHTRC <- pmax(300, 0.10 * TAXDATA2$NetBill)
  } else {
    TAXDATA2$SuppHTRC <- 0
  }

  TAXDATA2$ActualNonExemptBill <- TAXDATA2$NetBill - TAXDATA2$SuppHTRC - TAXDATA2$TotalCredits
  TAXDATA2$ActualBill          <- TAXDATA2$ActualNonExemptBill + TAXDATA2$ExemptGrossBill

  out.TAXDATA <- TAXDATA2

  # Aggregate bill variables to district level for revenue allocation in step 9.
  bill_vars <- c("GrossTaxBill", "NonExemptGrossBill", "ExemptGrossBill",
                 "NetBill", "PTCLoss", "SuppHTRC", "ActualNonExemptBill", "ActualBill")
  aggTaxBills <- aggregate(
    out.TAXDATA[, bill_vars],
    by  = list(TAX_DIST_CD = out.TAXDATA$StateDistrict),
    FUN = sum, na.rm = TRUE
  )
  for (v in bill_vars) names(aggTaxBills)[names(aggTaxBills) == v] <- paste0("sum.", v)

  # ── Step 8: LocalFisc_Fund2 — rate shares ─────────────────────────────────
  # Aggregate the four rate components by TAX_DIST_CD × ExemptFund.
  # Summed rates are used to compute each fund's proportional revenue share.
  rate_vars <- c("FixedRate", "ResidRate", "ExemptRate", "NonExemptRate")
  rate_agg <- aggregate(
    LocalFisc_Fund[, rate_vars],
    by  = list(TAX_DIST_CD = LocalFisc_Fund$TAX_DIST_CD,
               ExemptFund  = LocalFisc_Fund$ExemptFund),
    FUN = sum, na.rm = TRUE
  )
  for (v in rate_vars) names(rate_agg)[names(rate_agg) == v] <- paste0("sum_", v)

  LocalFisc_Fund2 <- merge(LocalFisc_Fund, rate_agg, by = c("TAX_DIST_CD", "ExemptFund"))

  # Fund-level rate shares within district × ExemptFund group.
  LocalFisc_Fund2$shr_ExemptRate <- with(LocalFisc_Fund2,
    ifelse(!is.na(sum_ExemptRate)    & sum_ExemptRate    != 0,
           ExemptRate    / sum_ExemptRate,    0))
  LocalFisc_Fund2$shr_NonExemptRate <- with(LocalFisc_Fund2,
    ifelse(!is.na(sum_NonExemptRate) & sum_NonExemptRate != 0,
           NonExemptRate / sum_NonExemptRate, 0))
  LocalFisc_Fund2$shr_FixedRate <- with(LocalFisc_Fund2,
    ifelse(!is.na(sum_FixedRate)     & sum_FixedRate     != 0,
           FixedRate     / sum_FixedRate,     0))
  LocalFisc_Fund2$shr_ResidRate <- with(LocalFisc_Fund2,
    ifelse(!is.na(sum_ResidRate)     & sum_ResidRate     != 0,
           ResidRate     / sum_ResidRate,     0))

  # ── Step 9: Revenue allocation → out.BUDGETDATA, out.LocalFisc ────────────
  out.BUDGETDATA <- merge(LocalFisc_Fund2, aggTaxBills, by = "TAX_DIST_CD")

  # Revenue: distribute district bill totals across funds by rate share.
  #   Cap-exempt funds (ExemptFund = 1): share of total exempt gross bill.
  #   Non-exempt funds (NonExemptFund = 1): share of total actual non-exempt bill.
  out.BUDGETDATA$Revenue <- ifelse(
    out.BUDGETDATA$ExemptFund == 1,
    out.BUDGETDATA$shr_ExemptRate    * out.BUDGETDATA$`sum.ExemptGrossBill`,
    out.BUDGETDATA$shr_NonExemptRate * out.BUDGETDATA$`sum.ActualNonExemptBill`
  )

  # Unfunded: shortfall between certified levy and revenue, for non-exempt funds.
  out.BUDGETDATA$Unfunded <- ifelse(
    out.BUDGETDATA$NonExemptFund == 1,
    out.BUDGETDATA$`Certified Levy` - out.BUDGETDATA$Revenue,
    0
  )

  # Unit-level summary: aggregate Revenue and Unfunded by county, unit type,
  # and unit. UNIT_TYPE_CD is required because UNIT_CD is not unique within a
  # county across unit types (e.g. a city and a library may share the same code).
  out.LocalFisc <- aggregate(
    out.BUDGETDATA[, c("Revenue", "Unfunded")],
    by  = list(CNTY_CD      = out.BUDGETDATA$CNTY_CD,
               UNIT_TYPE_CD = out.BUDGETDATA$UNIT_TYPE_CD,
               UNIT_CD      = out.BUDGETDATA$UNIT_CD),
    FUN = sum, na.rm = TRUE
  )

  # ── Step 10: out.UnitFund — unit × fund validation table ──────────────────
  # Collapses out.BUDGETDATA from district × unit × fund to unit × fund and
  # merges in the submitted input BUDGETDATA values for side-by-side comparison.
  #
  # Certified Net Assessed Valuation, Certified Gross Tax Rate, and Certified
  # Levy are identical for all district rows of a given unit × fund (they are
  # unit-level quantities); the first occurrence is used to deduplicate.
  # Revenue and Unfunded vary by district and are summed to the unit × fund level.
  # Submitted values from the input BUDGETDATA are attached with a Sub_ prefix.

  uf_key <- c("CNTY_CD", "UNIT_TYPE_CD", "UNIT_CD", "FUND_CD")

  uf_const_cols <- c(uf_key, "UNIT_NAME", "FUND_LONG_NAME",
                     "Certified Net Assessed Valuation",
                     "Certified Gross Tax Rate",
                     "Certified Levy")
  uf_const <- out.BUDGETDATA[!duplicated(out.BUDGETDATA[, uf_key]), uf_const_cols]
  names(uf_const)[names(uf_const) == "Certified Net Assessed Valuation"] <- "Comp_CNAV"
  names(uf_const)[names(uf_const) == "Certified Gross Tax Rate"]         <- "Comp_CGR"
  names(uf_const)[names(uf_const) == "Certified Levy"]                   <- "Comp_Levy"

  uf_sums <- aggregate(
    out.BUDGETDATA[, c("Revenue", "Unfunded")],
    by  = list(CNTY_CD      = out.BUDGETDATA$CNTY_CD,
               UNIT_TYPE_CD = out.BUDGETDATA$UNIT_TYPE_CD,
               UNIT_CD      = out.BUDGETDATA$UNIT_CD,
               FUND_CD      = out.BUDGETDATA$FUND_CD),
    FUN = sum, na.rm = TRUE
  )
  names(uf_sums)[names(uf_sums) == "Revenue"]  <- "Comp_Revenue"
  names(uf_sums)[names(uf_sums) == "Unfunded"] <- "Comp_Unfunded"

  out.UnitFund <- merge(uf_const, uf_sums, by = uf_key)

  # Attach submitted BUDGETDATA values (county-filtered input, before processing).
  sub_cols <- c("County", "Unit Type Code", "Unit Code", "Fund",
                "Certified Net Assessed Valuation",
                "Certified Gross Tax Rate",
                "Certified Levy")
  sub_vals <- BUDGETDATA[, sub_cols]
  names(sub_vals)[names(sub_vals) == "Certified Net Assessed Valuation"] <- "Sub_CNAV"
  names(sub_vals)[names(sub_vals) == "Certified Gross Tax Rate"]         <- "Sub_CGR"
  names(sub_vals)[names(sub_vals) == "Certified Levy"]                   <- "Sub_Levy"

  out.UnitFund <- merge(
    out.UnitFund, sub_vals,
    by.x = c("CNTY_CD", "UNIT_TYPE_CD", "UNIT_CD", "FUND_CD"),
    by.y = c("County",  "Unit Type Code", "Unit Code", "Fund"),
    all.x = TRUE
  )

  # ── Return ─────────────────────────────────────────────────────────────────
  list(
    out.TAXDATA    = out.TAXDATA,
    out.BUDGETDATA = out.BUDGETDATA,
    out.LocalFisc  = out.LocalFisc,
    out.UnitFund   = out.UnitFund
  )
}
