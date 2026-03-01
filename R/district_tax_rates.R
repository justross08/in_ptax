# district_tax_rates.R
#
# Classifies each row in the tax district / unit / fund crosswalk and derives
# rate components used in property tax bill calculations and cap analysis.
#
# This function is the crosswalk-level analogue of budget_tax_rates(). It
# applies the same fund classification logic and produces the same eight
# derived columns, but operates on the district/unit crosswalk (xwalk) rather
# than the aggregate budget levy file. Because xwalk rows are district×unit×fund
# combinations, the output retains all identifying columns (TAX_DIST_CD,
# UNIT_CD, FUND_CD, etc.) alongside the new rate components.
#
# INPUTS
#   xwalk      Data frame from read_excel() on
#                2025_Certifed_Tax_Rates_by_District_Unit.xlsx.
#              Key columns used:
#                FUND_CD             — 4-char zero-padded fund code
#                CERTD_TAX_RATE_PCNT — certified tax rate ($/100 AV)
#   FRF        Data frame from read_excel() on Fixed_Rate_Cap_Funds.xlsx.
#              Key column used:
#                Fund                — 4-char fund codes for fixed-rate
#                                      cumulative capital funds
#   CapExempt  Data frame from read_excel() on CapExemptFunds.xlsx.
#              Key column used:
#                Fund Code           — 4-char fund codes for funds exempt
#                                      from the property tax circuit breaker
#
# OUTPUT
#   xwalk with eight columns added:
#
#   RateFund      1 if the fund is a fixed-rate cumulative capital fund
#                 (found in FRF); 0 otherwise.
#   ResidFund     1 - RateFund. Standard (residual) levy-based funds.
#   ExemptFund    1 if the fund is exempt from the property tax circuit
#                 breaker cap (found in CapExempt); 0 otherwise.
#   NonExemptFund 1 - ExemptFund.
#   FixedRate     CERTD_TAX_RATE_PCNT for fixed-rate funds; 0 for all others.
#   ResidRate     CERTD_TAX_RATE_PCNT for residual (non-fixed-rate) funds;
#                 0 for fixed-rate funds.
#   ExemptRate    CERTD_TAX_RATE_PCNT for cap-exempt funds; 0 for all others.
#                 Used to compute the portion of a taxpayer's bill not subject
#                 to the circuit-breaker cap.
#   NonExemptRate CERTD_TAX_RATE_PCNT for non-exempt funds; 0 for exempt funds.
#                 Used to compute the portion of a taxpayer's bill subject to
#                 capping.
#
# NOTE
#   CERTD_TAX_RATE_PCNT is already in $/100 AV as imported from Excel
#   (no implied-decimal scaling required, unlike FWF files).
#   Fund code matching is exact string comparison on the 4-char FUND_CD field.
#   Both FRF$Fund and CapExempt$`Fund Code` use the same zero-padded format
#   as xwalk$FUND_CD (e.g. "0021", "0191").

district_tax_rates <- function(xwalk, FRF, CapExempt) {

  # ── Fund classification dummies ────────────────────────────────────────────

  # Fixed-rate cumulative capital funds
  xwalk$RateFund  <- as.integer(xwalk$FUND_CD %in% FRF$Fund)
  xwalk$ResidFund <- 1L - xwalk$RateFund

  # Circuit-breaker cap exempt funds
  xwalk$ExemptFund    <- as.integer(xwalk$FUND_CD %in% CapExempt$`Fund Code`)
  xwalk$NonExemptFund <- 1L - xwalk$ExemptFund

  # ── Rate components ────────────────────────────────────────────────────────

  # FixedRate: rate for fixed-rate funds only; 0 for all others
  xwalk$FixedRate <- xwalk$CERTD_TAX_RATE_PCNT * xwalk$RateFund

  # ResidRate: rate for standard levy-based funds only; 0 for fixed-rate funds
  xwalk$ResidRate <- xwalk$CERTD_TAX_RATE_PCNT * xwalk$ResidFund

  # ExemptRate: rate for circuit-breaker cap exempt funds only; 0 for all others
  xwalk$ExemptRate <- xwalk$CERTD_TAX_RATE_PCNT * xwalk$ExemptFund

  # NonExemptRate: rate for non-exempt funds only; 0 for exempt funds
  xwalk$NonExemptRate <- xwalk$CERTD_TAX_RATE_PCNT * xwalk$NonExemptFund

  xwalk
}
