# budget_tax_rates.R
#
# Classifies each fund row in BUDGETDATA and derives rate components used in
# property tax bill calculations and cap analysis.
#
# INPUTS
#   BUDGETDATA   Data frame from read_excel() on
#                  2025_Certifed_Budget_Levy_CNAV_Rate_by_Fund.xlsx.
#                Key columns used:
#                  Fund                    — 4-char zero-padded fund code
#                  Certified Gross Tax Rate — gross rate ($/100 AV)
#   FRF          Data frame from read_excel() on Fixed_Rate_Cap_Funds.xlsx.
#                Key column used:
#                  Fund                    — 4-char fund codes for fixed-rate
#                                            cumulative capital funds
#   CapExempt    Data frame from read_excel() on CapExemptFunds.xlsx.
#                Key column used:
#                  Fund Code               — 4-char fund codes for funds exempt
#                                            from the property tax circuit breaker
#
# OUTPUT
#   BUDGETDATA with eight columns added:
#
#   RateFund      1 if the fund is a fixed-rate cumulative capital fund
#                 (found in FRF); 0 otherwise. For these funds the levy is
#                 derived from the rate, not the other way around.
#   ResidFund     1 - RateFund. Standard (residual) levy-based funds.
#   ExemptFund    1 if the fund is exempt from the property tax circuit
#                 breaker cap (found in CapExempt); 0 otherwise.
#   NonExemptFund 1 - ExemptFund.
#   FixedRate     Certified Gross Tax Rate for fixed-rate funds; 0 for all others.
#   ResidRate     Certified Gross Tax Rate for residual (non-fixed-rate) funds;
#                 0 for fixed-rate funds.
#   ExemptRate    Certified Gross Tax Rate for cap-exempt funds; 0 for all others.
#                 Used to compute the portion of a taxpayer's bill that is not
#                 subject to the circuit-breaker cap.
#   NonExemptRate Certified Gross Tax Rate for non-exempt funds; 0 for exempt funds.
#                 Used to compute the portion of a taxpayer's bill subject to capping.
#
# NOTE
#   Fund code matching is exact string comparison on the 4-char Fund field.
#   Both FRF$Fund and CapExempt$`Fund Code` use the same zero-padded format
#   as BUDGETDATA$Fund (e.g. "0021", "0191").

budget_tax_rates <- function(BUDGETDATA, FRF, CapExempt) {

  # ── Fund classification dummies ────────────────────────────────────────────

  # Fixed-rate cumulative capital funds
  BUDGETDATA$RateFund  <- as.integer(BUDGETDATA$Fund %in% FRF$Fund)
  BUDGETDATA$ResidFund <- 1L - BUDGETDATA$RateFund

  # Circuit-breaker cap exempt funds
  BUDGETDATA$ExemptFund    <- as.integer(BUDGETDATA$Fund %in% CapExempt$`Fund Code`)
  BUDGETDATA$NonExemptFund <- 1L - BUDGETDATA$ExemptFund

  # ── Rate components ────────────────────────────────────────────────────────

  # FixedRate: rate for fixed-rate funds only; 0 for all others
  BUDGETDATA$FixedRate <- BUDGETDATA$`Certified Gross Tax Rate` * BUDGETDATA$RateFund

  # ResidRate: rate for standard levy-based funds only; 0 for fixed-rate funds
  BUDGETDATA$ResidRate <- BUDGETDATA$`Certified Gross Tax Rate` * BUDGETDATA$ResidFund
  
  # ExemptRate: rate for circuit-breaker cap exempt funds only; 0 for all others
  BUDGETDATA$ExemptRate <- BUDGETDATA$`Certified Gross Tax Rate` * BUDGETDATA$ExemptFund
  
  # NonExemptRate: rate for non-exempt funds only; 0 for exempt funds
  BUDGETDATA$NonExemptRate <- BUDGETDATA$`Certified Gross Tax Rate` * BUDGETDATA$NonExemptFund

  BUDGETDATA
}
