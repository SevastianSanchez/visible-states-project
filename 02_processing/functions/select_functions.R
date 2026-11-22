# ==============================================================================
# select_functions.R -- the 2-98% rule, written once.
#
# Sourced, never run. Used by 04_select_model_series_sdg.R, by
# 05_validate_data_sdg.R, and again by the bootstrap and held-out checks in
# 03_measures, which re-apply the rule inside each goal.
# ==============================================================================

# Which columns of a 0/1 matrix pass the 2-98% rule. `M` has one column per
# series and one row per country-year; `lo` and `hi` are the cutoffs from
# rules.R (item_lo, item_hi). Returns one TRUE/FALSE per column: TRUE = the
# series is reported in more than `lo` and less than `hi` of country-years.
filter_prevalence <- function(M, lo, hi) {
  p <- colMeans(M)
  p > lo & p < hi
}
