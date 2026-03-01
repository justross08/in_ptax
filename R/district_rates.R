# district_rates.R
#
# Aggregates fund-level tax rates from the district/unit/fund crosswalk to
# the tax district level by summing across all unit-fund rows within each
# district.
#
# This function expects the output of district_tax_rates() as its input —
# i.e., a crosswalk data frame that already has the five rate columns
# (CERTD_TAX_RATE_PCNT, FixedRate, ResidRate, ExemptRate, NonExemptRate)
# populated. Each row in that input is one district × unit × fund combination;
# summing within CNTY_CD + TAX_DIST_CD yields the single composite tax rate
# that applies to every parcel in the district.
#
# INPUT
#   xwalk  Data frame returned by district_tax_rates(). Must contain:
#            CNTY_CD             — county code
#            TAX_DIST_CD         — tax district code
#            TAX_DIST_NAME       — tax district name (1:1 with TAX_DIST_CD)
#            CERTD_TAX_RATE_PCNT — total fund rate ($/100 AV)
#            FixedRate           — rate for fixed-rate capital funds
#            ResidRate           — rate for standard levy-based funds
#            ExemptRate          — rate for cap-exempt funds
#            NonExemptRate       — rate for non-exempt funds
#
# OUTPUT
#   Data frame with one row per CNTY_CD + TAX_DIST_CD. Columns:
#
#   CNTY_CD             — county code
#   TAX_DIST_CD         — tax district code
#   TAX_DIST_NAME       — tax district name
#   CERTD_TAX_RATE_PCNT — sum of all fund rates in the district ($/100 AV);
#                         should equal the LocalTaxRate in TAXDATA for parcels
#                         in this district (after the 2.4-format implied decimal
#                         is applied at import)
#   FixedRate           — sum of fixed-rate fund rates in the district
#   ResidRate           — sum of residual (levy-based) fund rates in the district
#   ExemptRate          — sum of cap-exempt fund rates in the district
#   NonExemptRate       — sum of non-exempt fund rates in the district
#
# NOTE
#   All rate columns are in $/100 AV. To obtain a decimal multiplier for
#   multiplication against assessed value, divide by 100.
#   Rows are returned sorted by CNTY_CD then TAX_DIST_CD.

district_rates <- function(xwalk) {

  rate_cols <- c("CERTD_TAX_RATE_PCNT", "FixedRate", "ResidRate",
                 "ExemptRate", "NonExemptRate")

  agg <- aggregate(
    xwalk[rate_cols],
    by = list(
      CNTY_CD       = xwalk$CNTY_CD,
      TAX_DIST_CD   = xwalk$TAX_DIST_CD,
      TAX_DIST_NAME = xwalk$TAX_DIST_NAME
    ),
    FUN  = sum,
    na.rm = TRUE
  )

  district_rates<-agg[order(agg$CNTY_CD, agg$TAX_DIST_CD), ]
}
