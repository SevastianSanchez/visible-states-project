# ==============================================================================
# 05_validate_data_sdg.R -- the gate before any model runs.
#
# Step 5 of 5: 01 extract -> 02 clean -> 03 wrangle -> 04 select model series
#              -> 05 validate
#
# This validates the DATA. (The validate_measure/ folders in 03_measures
# validate the MEASURE, after a model is fitted.)
#
# Every check must pass. If one fails, the run stops and says which check and
# why; nothing downstream should be fitted on data that fails here.
#
# EXPECTED COUNTS are written below on purpose. A new UN export will change
# them; when it does, this script stops, someone checks the change is real,
# and the expected counts are updated here with a METHODS_LOG.md row.
#
# INPUT   01_data/processed/sdg_full_data.csv.gz, geo_exclusions.csv,
#         grid_all_series.rds, grid_model_series.rds, series_goal.csv,
#         series_variant_map.csv, filter_log.csv
# OUTPUT  none (prints each check)
# ==============================================================================

source(here::here("packages.R"))
library(here)
suppressPackageStartupMessages(library(data.table))
source(here("rules.R"))
source(here("02_processing/functions/select_functions.R"))

expected <- list(countries = 197L, country_years = 1773L,
                 series_all = 665L, series_model = 524L)

dir <- here("01_data/processed")
raw        <- fread(file.path(dir, "sdg_full_data.csv.gz"),
                    select = c("geo_area_code", "iso3", "year"),
                    colClasses = list(character = "geo_area_code"))
excl       <- fread(file.path(dir, "geo_exclusions.csv"),
                    colClasses = list(character = "geo_area_code"))
grid_all   <- readRDS(file.path(dir, "grid_all_series.rds"))
grid_model <- readRDS(file.path(dir, "grid_model_series.rds"))
series_goal <- fread(file.path(dir, "series_goal.csv"),
                     colClasses = list(character = "goals_listed"))
vmap       <- fread(file.path(dir, "series_variant_map.csv"))
flog       <- fread(file.path(dir, "filter_log.csv"))

failures <- character(0)
check <- function(ok, what) {
  cat(if (ok) "  pass  " else "  FAIL  ", what, "\n", sep = "")
  if (!ok) failures <<- c(failures, what)
}

cat("\nThe cleaned rows\n")
check(!anyNA(raw$iso3), "every row has an ISO3 code")
check(all(raw$year >= start_year & raw$year <= end_year),
      paste0("every year is inside ", start_year, "-", end_year, " (rules.R)"))
check(!any(raw$geo_area_code %in% excl[disposition == "excluded"]$geo_area_code),
      "none of the excluded places is left in the data")
check(!any(raw$geo_area_code %in% excl[disposition == "rolled up"]$geo_area_code),
      "none of the rolled-up places is left under its own code")
check(uniqueN(raw$iso3) == expected$countries,
      paste0(expected$countries, " countries (found ", uniqueN(raw$iso3), ")"))

cat("\nThe full grid (grid_all_series.rds)\n")
keys <- grid_all[, .(iso3, year)]
check(nrow(grid_all) == expected$country_years,
      paste0(expected$country_years, " country-years (found ", nrow(grid_all), ")"))
check(!anyDuplicated(keys), "no country-year appears twice")
check(all(keys[, .N, by = iso3]$N == length(start_year:end_year)),
      "every country has every year")
check(setequal(unique(grid_all$iso3), unique(raw$iso3)),
      "the grid has exactly the countries in the cleaned rows")
vals <- as.matrix(grid_all[, -(1:2)])
check(!anyNA(vals) && all(vals %in% c(0L, 1L)), "every cell is 0 or 1, none missing")
check(ncol(vals) == expected$series_all,
      paste0(expected$series_all, " series (found ", ncol(vals), ")"))

cat("\nThe model grid (grid_model_series.rds)\n")
mvals <- as.data.frame(grid_model[, -(1:2)])
check(identical(grid_model$iso3, keys$iso3) && identical(grid_model$year, keys$year),
      "same country-years, in the same order, as the full grid")
check(all(names(mvals) %in% names(grid_all)),
      "every model series is in the full grid")
check(all(filter_prevalence(mvals, item_lo, item_hi)),
      paste0("every model series is reported in more than ", item_lo * 100,
             "% and less than ", item_hi * 100, "% of country-years (rules.R)"))
check(ncol(mvals) == expected$series_model,
      paste0(expected$series_model, " series (found ", ncol(mvals), ")"))
dup_kept <- vmap[verdict == "collapse" & series_code != cluster]$series_code
check(!any(dup_kept %in% names(mvals)),
      "only one series from each duplicate group is kept")
together <- vmap[verdict == "collapse", {
  sub <- vals[, series_code, drop = FALSE]
  .(ok = all(apply(sub, 1, function(z) length(unique(z)) == 1)))
}, by = cluster]
check(all(together$ok), "every duplicate group moves as one in every country-year")

cat("\nOne goal per series (series_goal.csv)\n")
check(setequal(series_goal$series_code, names(mvals)) &&
        !anyDuplicated(series_goal$series_code),
      "every model series has exactly one row")
check(all(series_goal$goal_assigned %in% 1:17), "every assigned goal is 1-17")
check(all(mapply(function(a, l) a %in% as.integer(strsplit(l, "/")[[1]]),
                 series_goal$goal_assigned, series_goal$goals_listed)),
      "every series is assigned to one of its own goals")

cat("\nThe series count after each rule (filter_log.csv)\n")
check(identical(flog$series[c(1, 4)], c(expected$series_all, expected$series_model)),
      paste0("the log runs from ", expected$series_all, " to ", expected$series_model))
check(all(diff(flog$series) <= 0), "the count never rises from one rule to the next")
print(flog)

if (length(failures))
  stop(length(failures), " check(s) failed:\n", paste0("  - ", failures, collapse = "\n"),
       "\nDo not fit any model on this data.", call. = FALSE)
cat("\nAll checks passed. The data is ready for the models.\n")
