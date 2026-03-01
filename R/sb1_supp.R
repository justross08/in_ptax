# sb1_supp.R
#
# Applies two SB 1 (2025) policy changes to ADJMENTS:
#
#   1. HOMESTEAD DEDUCTION PHASE-IN (assessment years 2025–2030+)
#      Revises TotalAdjustAmount for AdjstCode "3" (standard deduction) and
#      "64" (supplemental deduction) according to the phase-in schedule below.
#
#   2. LOCAL INCOME TAX CREDIT ELIMINATION (assessment years 2027+)
#      Zeros TotalAdjustAmount for AdjstCodes 57–60 and 77–83 (local income
#      tax credits used for property tax replacement). These credits are fully
#      eliminated starting in assessment year 2027.
#
# INPUTS
#   assessment_year  Numeric. Assessment year for which to apply policy changes.
#   TAXDATA          Data frame from read_taxdata(). Must contain ParcelNum and GrossAV.
#                    Required for homestead deduction calculations.
#   ADJMENTS         Data frame from read_adjust(). Updated rows:
#                      AdjstCode "3"    — standard deduction (2025+)
#                      AdjstCode "64"   — supplemental deduction (2025+)
#                      AdjstCodes 57–60 — income tax relief credits (zeroed 2027+)
#                      AdjstCodes 77–83 — additional LOIT relief credits (zeroed 2027+)
#
# OUTPUT
#   A copy of ADJMENTS with TotalAdjustAmount revised for affected rows.
#   All other rows are returned unchanged.
#
# NOTES
#   - AdjstAmt1 / AdjstAmt2 / AdjstAmt3 are NOT updated; only TotalAdjustAmount.
#   - TotalAdjustAmount is in dollars; Format 12.2 implied decimal is applied
#     at import by read_adjust(). Example: $48,000 arrives as 48000.00.
#   - Only existing rows are modified. No rows are added or deleted.
#   - Total homestead deduction (standard + supplemental) is capped at 75% of
#     GrossAV per statute. Supplemental is reduced first; standard is reduced only
#     if standard alone exceeds 75% of GrossAV (applies to very low-value parcels).
#   - For assessment_year >= 2030, the 2030 homestead schedule is applied.
#   - For assessment_year < 2025, ADJMENTS is returned unchanged with a warning.
#   - ParcelNum and AdjstCode are trimmed of whitespace before matching.
#     readr::read_fwf (used in the updated readers) trims automatically, but
#     trimws() is kept here as a safety net for data from other sources.
#
# HOMESTEAD DEDUCTION PHASE-IN SCHEDULE
#   Year  Std Deduction Cap   Supplemental Rate (applied to remaining AV)
#   2025  $48,000             40%
#   2026  $40,000             46%
#   2027  $30,000             52%
#   2028  $20,000             57%
#   2029  $10,000             62%
#   2030+ $      0            66.7%
#
# LOCAL INCOME TAX CREDIT ELIMINATION
#   AdjstCodes 57–60, 77–83 set to 0 for assessment_year >= 2027.

sb1_supp <- function(assessment_year, TAXDATA, ADJMENTS) {

  # ── Phase-in schedule ──────────────────────────────────────────────────────
  schedule <- data.frame(
    year      = c(2025L, 2026L, 2027L, 2028L, 2029L, 2030L),
    std_cap   = c(48000, 40000, 30000, 20000, 10000,     0),
    supp_rate = c(0.400, 0.460, 0.520, 0.570, 0.620, 0.667),
    stringsAsFactors = FALSE
  )

  if (assessment_year < 2025) {
    warning("assessment_year is before 2025; SB 1 phase-in has not begun. ",
            "ADJMENTS returned unchanged.")
    return(ADJMENTS)
  }

  params    <- schedule[schedule$year == min(as.integer(assessment_year), 2030L), ]
  std_cap   <- params$std_cap
  supp_rate <- params$supp_rate

  # ── Identify homestead adjustment rows ─────────────────────────────────────
  # Trim whitespace; readr handles this automatically but trimws() is kept as a safety net
  adj_code <- trimws(as.character(ADJMENTS$AdjstCode))
  is_std   <- adj_code == "3"
  is_supp  <- adj_code == "64"
  is_hstd  <- is_std | is_supp

  homestead_parcels <- unique(trimws(as.character(ADJMENTS$ParcelNum[is_hstd])))

  if (length(homestead_parcels) == 0) {
    warning("No rows with AdjstCode '3' or '64' found in ADJMENTS. ",
            "ADJMENTS returned unchanged.")
    return(ADJMENTS)
  }

  # ── Pull GrossAV from TAXDATA for homestead parcels ────────────────────────
  taxdata_pnum <- trimws(as.character(TAXDATA$ParcelNum))
  av_rows      <- taxdata_pnum %in% homestead_parcels
  av           <- data.frame(
    ParcelNum = taxdata_pnum[av_rows],
    GrossAV   = TAXDATA$GrossAV[av_rows],
    stringsAsFactors = FALSE
  )

  missing <- setdiff(homestead_parcels, av$ParcelNum)
  if (length(missing) > 0) {
    warning(length(missing), " parcel(s) with homestead adjustments not found in TAXDATA. ",
            "TotalAdjustAmount will not be updated for those parcels.")
  }

  # Drop parcels with missing GrossAV before computing deductions
  na_av <- is.na(av$GrossAV)
  if (any(na_av)) {
    warning(sum(na_av), " parcel(s) have NA GrossAV in TAXDATA. ",
            "TotalAdjustAmount will not be updated for those parcels.")
    av <- av[!na_av, ]
  }

  if (nrow(av) == 0) {
    warning("No parcels with valid GrossAV remain. ADJMENTS returned unchanged.")
    return(ADJMENTS)
  }

  # ── Compute new deduction amounts per parcel ───────────────────────────────
  gav      <- av$GrossAV
  new_std  <- pmin(gav, std_cap)                   # standard: min(GrossAV, cap)
  remaining <- pmax(0, gav - new_std)              # remaining AV above the cap
  new_supp <- supp_rate * remaining                # supplemental: rate * remaining

  # 75% statutory cap on total deduction (standard + supplemental combined)
  max_allowed <- 0.75 * gav
  total        <- new_std + new_supp
  over         <- total > max_allowed

  if (any(over, na.rm = TRUE)) {
    # Reduce supplemental first
    new_supp[over] <- pmax(0, max_allowed[over] - new_std[over])
    # If standard alone exceeds cap (very low-value parcels), reduce standard too
    std_over           <- over & (new_std > max_allowed)
    new_std[std_over]  <- max_allowed[std_over]
    new_supp[std_over] <- 0
  }

  # Round to cents (consistent with Format 12.2 precision in source data)
  std_stored  <- round(new_std,  2)
  supp_stored <- round(new_supp, 2)

  # Named vectors for vectorized lookup by ParcelNum
  std_lookup  <- setNames(std_stored,  av$ParcelNum)
  supp_lookup <- setNames(supp_stored, av$ParcelNum)

  # ── Update ADJMENTS ────────────────────────────────────────────────────────
  ADJMENTS_out  <- ADJMENTS
  adj_pnum      <- trimws(as.character(ADJMENTS_out$ParcelNum))
  matched       <- adj_pnum %in% av$ParcelNum

  # Standard deduction rows
  idx_std <- which(is_std & matched)
  if (length(idx_std) > 0) {
    ADJMENTS_out$TotalAdjustAmount[idx_std] <- std_lookup[adj_pnum[idx_std]]
  }

  # Supplemental deduction rows
  idx_supp <- which(is_supp & matched)
  if (length(idx_supp) > 0) {
    ADJMENTS_out$TotalAdjustAmount[idx_supp] <- supp_lookup[adj_pnum[idx_supp]]
  }

  # ── Zero out local income tax credits (assessment_year >= 2027) ────────────
  # AdjstCodes 57–60: income tax relief credits for property tax replacement
  # AdjstCodes 77–83: additional LOIT for property tax relief
  # All eliminated by statute starting in assessment year 2027.
  if (assessment_year >= 2027) {
    loit_codes <- as.character(c(57:60, 77:83))
    is_loit    <- adj_code %in% loit_codes
    idx_loit   <- which(is_loit)
    if (length(idx_loit) > 0) {
      ADJMENTS_out$TotalAdjustAmount[idx_loit] <- 0
    }
  }

  ADJMENTS_out
}
