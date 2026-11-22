# run_all.R -- runs the Visible States pipeline in order: processing, then the
# models, then the checks on the models. It never publishes anything, and it
# does not run the diagnostics (02_processing/diagnostics/), which are reports
# to run by hand.
#
#   Rscript run_all.R                 processing and quick checks (~minutes)
#   FITS=1   Rscript run_all.R        also refit vsi and vsi_goal (read METHODS_LOG.md first)
#   CHECKS=1 Rscript run_all.R        also run the vsi_goal held-out check
#
# Never run with FITS=1 without reading METHODS_LOG.md: every fit is recorded
# there, along with the configurations that already failed.
#
# Steps 01-03 need the 17 UN exports in 01_data/raw/un_sdg_exports/, which are
# not on GitHub (310 MB; the README says how to download them). Without them,
# the run starts at step 04 from the processed files that are on GitHub.
#
# The bifactor (03_measures/vsi_goal_relative) and both bootstraps take hours
# and are never run from here; run them on their own, chunked.

library(here)
step <- function(f) {
  cat(sprintf("\n[%s] %s\n", format(Sys.time(), "%H:%M:%S"), f))
  status <- system2("Rscript", here(f))
  if (status != 0) stop("failed: ", f, call. = FALSE)
}
on <- function(v) identical(Sys.getenv(v), "1")

# ---- processing --------------------------------------------------------------
exports <- list.files(here("01_data/raw/un_sdg_exports"), pattern = "^Goal.*\\.xlsx$")
if (length(exports) == 17) {
  step("02_processing/01_extract_sdg.R")
  step("02_processing/02_clean_sdg.R")
  step("02_processing/03_wrangle_sdg.R")
} else {
  cat("\nUN exports not found: starting at step 04 from the processed files.\n")
}
step("02_processing/04_select_model_series_sdg.R")
step("02_processing/05_validate_data_sdg.R")
step("02_processing/extract_covariates.R")
step("02_processing/build_count_measures.R")

# ---- models ------------------------------------------------------------------
if (on("FITS")) {
  step("03_measures/vsi/build_irt_vsi.R")
  step("03_measures/vsi_goal/build_irt_vsi_goal.R")
}

# ---- checks on the models ----------------------------------------------------
step("03_measures/vsi/validate_measure/validate_vsi_external_measures.R")
if (on("CHECKS")) step("03_measures/vsi_goal/validate_measure/validate_vsi_goal_heldout.R")
cat("\ndone.\n")
