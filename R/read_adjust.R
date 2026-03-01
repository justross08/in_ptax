# read_adjust.R
# Reads the ADJMENTS fixed-width file (DLGF, pay year 2025).
# Layout: 50 IAC 26, pp. 96-97. 10 columns.
#
# Requires the readr package.
#
# COLUMN TYPES
#   Character: ParcelNum, AdjstTypeCode, AdjstCode, StartYear.
#              AdjstCode read as character to preserve exact string values
#              (e.g. "3", "57", "64") and prevent numeric coercion.
#              StartYear is type A in the spec (four-digit year as text).
#   Double:    AdjustInstNum, TotalAdjustAmount, AdjstAmt1, AdjstAmt2,
#              AdjstAmt3, NumYears.
#
# KEY CODES
#   AdjstTypeCode (PTMS List 65):  C = Credit, E = Exemption, D = Deduction
#   AdjstCode     (PTMS List 37):  see data/AdjustCodes.xlsx
#     "3"       = Standard Deduction
#     "64"      = Supplemental Standard Deduction
#     "57"–"59" = Income tax relief credits for property tax replacement
#     "60"      = LOIT for Property Tax Relief Credit
#     "77"–"83" = Additional LOIT for Property Tax Relief
#
# IMPLIED DECIMAL SCALING (applied after read, per 50 IAC 26 format specs)
#   Format 12.2 — all four amount columns: raw integer divided by 100.
#     Columns: TotalAdjustAmount, AdjstAmt1, AdjstAmt2, AdjstAmt3.
#     Example: raw 00000013000050 -> 130000.50
#     Relationship: TotalAdjustAmount = AdjstAmt1 + AdjstAmt2 + AdjstAmt3.
#   No scaling: AdjustInstNum, NumYears (plain integers).
#
# NA HANDLING
#   Blank and whitespace-only fields are returned as NA.
#
# WHITESPACE
#   readr trims leading/trailing whitespace from character columns by default
#   (trim_ws = TRUE). Downstream trimws() calls are not required.

read_adjust <- function(file) {

  w <- c(25, 3, 1, 2, 14, 14, 14, 14, 4, 2)

  cnames <- c(
    "ParcelNum", "AdjustInstNum", "AdjstTypeCode", "AdjstCode",
    "TotalAdjustAmount", "AdjstAmt1", "AdjstAmt2", "AdjstAmt3",
    "StartYear", "NumYears"
  )

  adj <- readr::read_fwf(
    file,
    col_positions = readr::fwf_widths(w, col_names = cnames),
    col_types = readr::cols(
      .default      = readr::col_double(),
      ParcelNum     = readr::col_character(),
      AdjstTypeCode = readr::col_character(),
      AdjstCode     = readr::col_character(),
      StartYear     = readr::col_character()
    ),
    skip           = 1,
    na             = c("", " "),
    show_col_types = FALSE
  )

  # ── Apply implied decimal scaling per 50 IAC 26 ────────────────────────────

  # Format 12.2: all adjustment amount columns — divide by 100
  amount_cols <- c("TotalAdjustAmount", "AdjstAmt1", "AdjstAmt2", "AdjstAmt3")
  adj[amount_cols] <- adj[amount_cols] / 100

  adj
}
