# read_taxdata.R
# Reads the TAXDATA fixed-width file (DLGF, pay year 2025).
# Layout: 50 IAC 26, pp. 93-95. 49 columns.
#
# Requires the readr package.
#
# COLUMN TYPES
#   Character: ParcelNum, AuditID, PropertyType, TaxpayerName, TPAddress,
#              TPCity, TPState, TPZIP, TPCTRY, PropAddress, PropCity, PropZIP,
#              TaxDistrict, StateDistrict, Township, School, Blind.
#              Read as character to preserve leading zeros in code fields
#              (TaxDistrict, Township, School, etc.).
#   Double:    All remaining columns (AV fields, tax amounts, rates).
#
# IMPLIED DECIMAL SCALING (applied after read, per 50 IAC 26 format specs)
#   Format 12.2 — dollar amount columns: raw integer divided by 100.
#     Columns: LatePPPenalty, UVPPRPenalty, PriorD, PriorPenalty, TotalBill,
#              GrossTaxDue, LocalTaxRelief, PropertyTaxCap, NetTaxDue,
#              OtherCharges, OverdueTaxes.
#     Example: raw 00000013000050 -> 130000.50
#   Format 2.4 — tax rate: raw integer divided by 10000.
#     Column: LocalTaxRate.
#     Example: raw 012345 -> 1.2345 (dollars per $100 AV).
#   No scaling: all AV columns (plain integers in whole dollars).
#
# NA HANDLING
#   Blank and whitespace-only fields are returned as NA.
#   Numeric NAs should be handled explicitly by the caller; do not replace
#   with 0 globally — character fields would be corrupted.
#
# WHITESPACE
#   readr trims leading/trailing whitespace from character columns by default
#   (trim_ws = TRUE). Downstream trimws() calls are not required.

read_taxdata <- function(file) {

  w <- c(25, 25,  1, 80, 60, 30, 30, 10,  3,
         60, 30, 10,  3,  3,  4,  4,
         14, 14, 14, 14, 14,
         12, 12, 12,
         12, 12,
         12, 12, 12, 12, 12, 12, 12, 12,
         12, 12, 12, 12, 12, 12, 12,
          6,
         14, 14, 14, 14, 14, 14,  1)

  cnames <- c(
    "ParcelNum", "AuditID", "PropertyType", "TaxpayerName",
    "TPAddress", "TPCity", "TPState", "TPZIP", "TPCTRY",
    "PropAddress", "PropCity", "PropZIP",
    "TaxDistrict", "StateDistrict", "Township", "School",
    "LatePPPenalty", "UVPPRPenalty", "PriorD", "PriorPenalty", "TotalBill",
    "AVLand", "AVImprove", "TotalAV",
    "AVLandCap1", "AVImprovCap1",
    "AVNHRLandCap2", "AVNHRImprovCap2",
    "AVCommLandCap2", "AVCommImprovCap2",
    "AVLTCLandCap2", "AVLTCImprovCap2",
    "AVFarmCap2", "AVMobileLandCap2",
    "AVLandCap3", "AVImprovCap3",
    "AVPPLocal", "AVPPState", "AV_TIF",
    "GrossAV", "NetAV", "LocalTaxRate",
    "GrossTaxDue", "LocalTaxRelief", "PropertyTaxCap", "NetTaxDue",
    "OtherCharges", "OverdueTaxes", "Blind"
  )

  td <- readr::read_fwf(
    file,
    col_positions = readr::fwf_widths(w, col_names = cnames),
    col_types = readr::cols(
      .default      = readr::col_double(),
      ParcelNum     = readr::col_character(),
      AuditID       = readr::col_character(),
      PropertyType  = readr::col_character(),
      TaxpayerName  = readr::col_character(),
      TPAddress     = readr::col_character(),
      TPCity        = readr::col_character(),
      TPState       = readr::col_character(),
      TPZIP         = readr::col_character(),
      TPCTRY        = readr::col_character(),
      PropAddress   = readr::col_character(),
      PropCity      = readr::col_character(),
      PropZIP       = readr::col_character(),
      TaxDistrict   = readr::col_character(),
      StateDistrict = readr::col_character(),
      Township      = readr::col_character(),
      School        = readr::col_character(),
      Blind         = readr::col_character()
    ),
    skip           = 1,
    na             = c("", " "),
    show_col_types = FALSE
  )

  # ── Apply implied decimal scaling per 50 IAC 26 ────────────────────────────

  # Format 12.2: dollar amount columns — divide by 100
  dollar_cols <- c("LatePPPenalty", "UVPPRPenalty", "PriorD", "PriorPenalty",
                   "TotalBill", "GrossTaxDue", "LocalTaxRelief",
                   "PropertyTaxCap", "NetTaxDue", "OtherCharges", "OverdueTaxes")
  td[dollar_cols] <- td[dollar_cols] / 100

  # Format 2.4: LocalTaxRate — divide by 10000
  # Result is dollars per $100 AV (e.g. raw 012345 -> 1.2345 $/100 AV)
  td$LocalTaxRate <- td$LocalTaxRate / 10000

  td
}
