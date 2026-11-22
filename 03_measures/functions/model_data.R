# ==============================================================================
# model_data.R -- what every model script and validation check needs, set up
# the same way each time.
#
# Sourced, never run. Replaces functions/irt_prep.R: the grids and the goal
# assignment are now built once in 02_processing (03 and 04) and saved, so
# this file only turns those saved tables into the objects the model scripts
# use. Every model therefore fits the IDENTICAL matrix.
#
# Sourcing it also loads the packages the model scripts use and rules.R, in
# the order irt_prep.R loaded them.
# ==============================================================================

source(here::here("packages.R"))
library(here)
suppressPackageStartupMessages({
  library(data.table)   # not loaded by packages.R
  library(mirt)
})
source(here("rules.R"))
source(here("02_processing/functions/select_functions.R"))

msg <- function(...) cat(format(Sys.time(), "[%H:%M:%S] "), ..., "\n", sep = "")

# Turns the saved tables into the objects the model scripts use.
#   grid_all     grid_all_series.rds   (1,773 x 665, from 03_wrangle_sdg.R)
#   grid_model   grid_model_series.rds (1,773 x 524, from 04_select_model_series_sdg.R)
#   series_goal  series_goal.csv         (each model series and its one goal)
#   min_series   goals with fewer series than this get no goal factor (rules.R)
# Returns a list; list2env() puts its parts in the script's environment:
#   wide         the full grid with keys (the publishable matrix)
#   keys         iso3 + year, row-aligned with resp
#   resp         data.frame, one row per country-year, one 0/1 column per model series
#   p_rep, keep  share of country-years reporting each of the 665 series, and
#                whether it passed the 2-98% rule
#   item_goal    the goal assigned to each model series, in resp's column order
#   shared_log   the series listed under several goals, and the goal each got
#   spec, spec_levels, spec_idx
#                the goal factor per series for the bifactor model; goals with
#                fewer than min_series series (goal 7) are NA = overall factor only
model_inputs <- function(grid_all, grid_model, series_goal, min_series) {
  resp  <- as.data.frame(grid_model[, -(1:2)])
  p_rep <- colMeans(as.data.frame(grid_all[, -(1:2)]))
  keep  <- filter_prevalence(as.data.frame(grid_all[, -(1:2)]), item_lo, item_hi)

  item_goal <- series_goal[match(colnames(resp), series_code), goal_assigned]
  stopifnot(!any(is.na(item_goal)))
  series_goal <- copy(series_goal)[, goals_listed := as.character(goals_listed)]
  shared_log  <- series_goal[grepl("/", goals_listed)]

  spec <- item_goal
  general_only <- as.integer(names(which(table(item_goal) < min_series)))
  spec[spec %in% general_only] <- NA_integer_
  spec_levels <- sort(unique(spec[!is.na(spec)]))
  spec_idx    <- match(spec, spec_levels)   # mirt wants 1..K, NA allowed

  list(wide = grid_all, keys = grid_all[, .(iso3, year)], resp = resp,
       p_rep = p_rep, keep = keep, item_goal = item_goal, shared_log = shared_log,
       spec = spec, spec_levels = spec_levels, spec_idx = spec_idx)
}
