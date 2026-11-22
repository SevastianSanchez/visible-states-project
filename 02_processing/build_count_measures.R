# ==============================================================================
# build_count_measures.R -- the count-based measures that came before the VSI.
#
# NOT part of the index. Kept because the measurement paper compares the VSI
# with them (section 7.3, via 04_publish/paper_numbers.R), and the Politics of
# NAs paper keeps its own copy. They count reported observations or series per
# country, year and goal, and divide by different denominators.
#
#   goal_lvl_dv_data      observation counts (one per published value, so a
#                         country reporting national + urban + rural rows counts
#                         3) and five shares of them. One row per country x year
#                         x goal, plus one "overall" row per country-year.
#   agg_series_counts_rc  the same, counting series instead of values (a series
#                         counts once however many breakdowns it has).
#
# The "stable" columns use the stable-core flag from series_stability_list.csv
# (built in 03_wrangle_sdg.R, section 7).
#
# INPUT   01_data/processed/sdg_full_data.csv.gz
#         01_data/processed/series_stability_list.csv
#         01_data/processed/agg_series_depth.rds
# OUTPUT  01_data/processed/count_measures/goal_lvl_dv_data.csv (+ .rds with labels)
#         01_data/processed/count_measures/agg_series_counts_rc.csv
# ==============================================================================

library(here)
library(dplyr)
library(readr)
library(tidyr)
source(here("rules.R"))

output_folder <- here("01_data/processed/count_measures")
dir.create(output_folder, recursive = TRUE, showWarnings = FALSE)

# Baseline window for the _pct_baseline / _pct_goalbase measures: the first
# three SDG years. To use a single year instead, e.g. baseline_years <- 2017L.
baseline_years <- 2015:2017

# ---- Inputs ------------------------------------------------------------------
# Every column is read as text except year and goal, which are whole numbers,
# exactly as 03_wrangle_sdg.R holds them.
raw_data <- read_csv(here("01_data/processed/sdg_full_data.csv.gz"),
                     col_types = cols(.default = col_character(),
                                      year = col_integer(), goal = col_integer()),
                     progress = FALSE)
series_list <- read_csv(here("01_data/processed/series_stability_list.csv"),
                        col_types = cols(.default = col_character(),
                                         goal = col_integer()),
                        progress = FALSE)
stable_codes <- unique(series_list$series_code[series_list$is_stable_core == "TRUE"])
agg_series_depth <- readRDS(here("01_data/processed/agg_series_depth.rds"))

# One row per country, carrying the ISO3 code.
countries <- raw_data %>% distinct(geo_area_code, geo_area_name, iso3)

# ---- 1. All-goals vector → goals -------------------------------------------
# Precomputed once and reused by every downstream expand_grid.
goals <- sort(unique(series_list$goal))


# ---- 2. Per-goal totals → goal_totals ------------------------------
# n_series_in_goal    : distinct series codes per goal (denominator for the
#                       series-count availability shares in section 7).
# n_observations_in_goal : total disaggregated observations per goal (one row
#                       of raw_data = one observation), i.e. the size of each
#                       goal's data universe below the series-code level.
# obs_per_series      : mean observations per series code — how deep the
#                       disaggregation runs for a typical series in the goal.
goal_totals <- series_list %>%
  distinct(goal, series_code) %>%
  count(goal, name = "n_series_in_goal") %>%
  left_join(raw_data %>% filter(!is.na(value)) %>%
              count(goal, name = "n_observations_in_goal"),
    by = "goal") %>%
  mutate(obs_per_series = n_observations_in_goal / n_series_in_goal)


# ---- 3. Framework-wide series total → agg_series_total ---------------------
# Unique series codes across all goal exports (a series in two goals counted
# once). Denominator for the framework-wide availability share in section 7.
agg_series_total <- n_distinct(series_list$series_code)


# ---- 4. Country-goal baseline mean → baseline ------------------------------
# Mean raw observation count per country-goal across baseline_years. Missing
# country-goal-years in the baseline window are treated as real zeros (not
# unobserved), so a country that reported nothing in a baseline year does not
# inflate its own baseline by being averaged over observed years only.
# Helper so the all-series and stable-core baselines are computed identically.
make_baseline <- function(dat) {
  expand_grid(
      countries,
      year = baseline_years,
      goal = goals
    ) %>%
    left_join(
      dat %>% filter(!is.na(value)) %>%
        count(geo_area_code, year, goal, name = "n_observations"),
      by = c("geo_area_code", "year", "goal")
    ) %>%
    mutate(n_observations = coalesce(n_observations, 0L)) %>%
    group_by(geo_area_code, goal) %>%
    summarise(baseline_mean = mean(n_observations), .groups = "drop")
}

# One table, one row per country-goal, with BOTH baseline means side by side.
# They share the country-goal grain, so they belong in a single object
# The two columns differ only in which series feed them:
#   baseline_mean_all    — all series (see agg_series_total for the count)
#   baseline_mean_stable — stable-core series only (see length(stable_codes))
# The series counts are printed in the console rather than baked into
# the column names, since they change if the core window or the pull changes.
baseline <- make_baseline(raw_data) %>%
  rename(baseline_mean_all = baseline_mean) %>%
  left_join(
    make_baseline(raw_data %>% filter(series_code %in% stable_codes)) %>%
      rename(baseline_mean_stable = baseline_mean),
    by = c("geo_area_code", "goal")) %>%
  left_join(distinct(raw_data, geo_area_code, geo_area_name),
    by = "geo_area_code")

# Adding labels to the baseline means
attr(baseline$baseline_mean_all, "label") <-
  sprintf("Obs count — all %d series", agg_series_total)
attr(baseline$baseline_mean_stable, "label") <-
  sprintf("Obs count — %d framework-stable series", length(stable_codes))


# ---- 4b. Goal-level baseline mean → goal_baseline --------------------------
# Average of the country-goal baselines across ALL countries within each goal —
# i.e. what a typical country reported for this goal in baseline_years. Derived
# from `baseline`
# (section 4), so it uses the identical window and definitions; because the baseline
# panel is balanced (every country has all baseline years), the mean of the
# country means equals the goal's overall baseline mean.
#
# WHY IT EXISTS: the country-own baseline in section 4 is undefined (0) for ~90
# country-goals that had not begun reporting a goal by 2017, forcing NA in
# dv_n_observations_pct_baseline. This goal-level denominator is never 0 (some
# country always reports), so it gives a cross-goal-comparable measure defined
# for every country-goal-year — see the *_pct_goalbase columns in section 6.
goal_baseline <- baseline %>%
  group_by(goal) %>%
  summarise(goal_baseline_all    = mean(baseline_mean_all),
            goal_baseline_stable = mean(baseline_mean_stable),
            .groups = "drop")


# ---- 5. Goal-year frontier max → frontier ----------------------------------
# Max country-goal-year observation count within each goal-year. Descriptive-
# companion denominator ("share of the top reporter") for
# dv_n_observations_pct_frontier.
frontier <- raw_data %>%
  filter(!is.na(value)) %>%
  count(geo_area_code, year, goal, name = "n_observations") %>%
  group_by(year, goal) %>%
  summarise(frontier_max = max(n_observations), .groups = "drop")


# =============================================================================
# OBSERVATION COUNTS ===========================================================
# =============================================================================
# Each observation is one data point: a country reporting national + urban +
# rural rows contributes 3 to that goal's count, not 1. Section 7 has the
# coarser series-code view.

# ---- 6. Goal-level DV panel: goal_lvl_dv_data ------------------------------
# Grain: one row per country x year x (goal or overall), set by `scope`:
#   scope == "goal"    — per country-year-goal, goal 1-17 (the 17-goal panel)
#   scope == "overall" — per country-year, all goals aggregated, goal is NA
# Built on a full scaffold, so a cell that reported nothing shows a genuine 0,
# not a missing row. The overall rows apply the SAME denominators one grain up
# (see the overall-scope block below) — never summed from the goal ratios.
#
# All counts come from ONE pass over raw_data (.dv_counts): each column counts
# the rows meeting its own condition, so they all come from the same rows and a
# new breakdown is one more line, not another join. No rows are removed.
#
#   n_observations          reported observations (empty cells not counted)
#   n_observations_country  of those, the country produced it (nature C/CA)
#   n_observations_agency   of those, an agency produced it   (nature E/M/G)
#   n_observations_stable   of those, in the framework-stable core (03_wrangle_sdg.R section 7)
#   n_declared_missing      empty cells the UN opened here (split by reason)
#
# The country/agency split shows who produced the reported numbers: if agencies
# fill in for a country, n_observations can stay flat while
# n_observations_country falls. (They need not sum to n_observations — 0.05% of
# rows carry no nature code.)
#
# The _pct_* columns (added after the join below) put each goal on a comparable
# scale by dividing by a denominator. See section 4 / section 4b / section 5 for the three choices.
.dv_counts <- raw_data %>%
  group_by(geo_area_code, geo_area_name, year, goal) %>%
  summarise(
    n_observations         = sum(!is.na(value)),
    n_observations_country = sum(!is.na(value) & nature %in% c("C", "CA")),
    n_observations_agency  = sum(!is.na(value) & nature %in% c("E", "M", "G")),
    n_observations_stable  = sum(!is.na(value) & series_code %in% stable_codes),
    n_declared_missing     = sum(is.na(value)),
    # The declared-missing total split by WHY (missing_reason, derived in 02_clean_sdg.R).
    # These three sum to n_declared_missing. `structural` is the one to watch:
    # it is non-applicability, not data loss, so it arguably belongs out of the
    # denominator.
    n_missing_structural   = sum(is.na(value) & missing_reason == "structural"),
    n_missing_suppressed   = sum(is.na(value) & missing_reason == "suppressed"),
    n_missing_unknown      = sum(is.na(value) & missing_reason == "unknown"),
    .groups = "drop"
  )

# Shared helper: the five dv_ ratios, identical formula for both scopes.
# (baseline_mean_all/_stable, goal_baseline_all/_stable, frontier_max must exist.)
.add_dv_ratios <- function(df) {
  df %>% mutate(
    # Divided by THIS country's own 2015-17 mean. NA where that baseline is 0
    # (e.g. a country-goal that reported nothing at baseline).
    dv_n_observations_pct_baseline = if_else(baseline_mean_all > 0,
                                          n_observations / baseline_mean_all, NA_real_),
    dv_n_observations_stable_pct_baseline = if_else(baseline_mean_stable > 0,
                                          n_observations_stable / baseline_mean_stable, NA_real_),
    # Divided by the mean across ALL countries (section 4b). Denominator never 0, so
    # defined everywhere — keeps late-starting reporters in the analysis.
    dv_n_observations_pct_goalbase = if_else(goal_baseline_all > 0,
                                          n_observations / goal_baseline_all, NA_real_),
    dv_n_observations_stable_pct_goalbase = if_else(goal_baseline_stable > 0,
                                          n_observations_stable / goal_baseline_stable, NA_real_),
    # "vs the top reporter that year": the denominator moves yearly.
    dv_n_observations_pct_frontier = if_else(frontier_max > 0,
                                          n_observations / frontier_max, NA_real_)
  )
}
.count_cols <- c("n_observations", "n_observations_country", "n_observations_agency",
                 "n_observations_stable", "n_declared_missing",
                 "n_missing_structural", "n_missing_suppressed", "n_missing_unknown")

# ---- Goal scope: one row per country x year x goal (scope == "goal") ---------
.goal_panel <- expand_grid(countries, year = start_year:end_year, goal = goals) %>%
  left_join(.dv_counts, by = c("geo_area_code", "geo_area_name", "year", "goal")) %>%
  # A country-goal-year with no rows at all is a genuine zero, not unknown.
  mutate(across(all_of(.count_cols), ~ coalesce(.x, 0L))) %>%
  left_join(baseline, by = c("geo_area_code", "geo_area_name", "goal")) %>%
  left_join(goal_baseline, by = "goal") %>%
  left_join(frontier, by = c("year", "goal")) %>%
  .add_dv_ratios() %>%
  mutate(scope = "goal")

# ---- Overall scope: one row per country x year, aggregated across all goals --
# NOT summed from the goal-scope ratios (that would be meaningless — each has a
# different goal-specific denominator). Instead the SAME method is applied one
# grain up: counts summed across goals, and each denominator re-derived without
# the goal split. `goal` is NA on these rows; filter with scope == "overall".
.dv_counts_overall <- .dv_counts %>%
  group_by(geo_area_code, geo_area_name, year) %>%
  summarise(across(all_of(.count_cols), sum), .groups = "drop")

# Overall own-baseline = this country's total across all goals, 2015-17 mean.
# Equals the sum of its per-goal baselines (mean and sum commute).
.baseline_overall <- baseline %>%
  group_by(geo_area_code, geo_area_name) %>%
  summarise(baseline_mean_all    = sum(baseline_mean_all),
            baseline_mean_stable = sum(baseline_mean_stable), .groups = "drop")
# Overall goalbase = mean of that across ALL countries (one scalar, no goal dim).
.gb_overall_all    <- mean(.baseline_overall$baseline_mean_all)
.gb_overall_stable <- mean(.baseline_overall$baseline_mean_stable)
# Overall frontier = max country total per year.
.frontier_overall <- raw_data %>%
  filter(!is.na(value)) %>%
  count(geo_area_code, year, name = "n_observations") %>%
  group_by(year) %>%
  summarise(frontier_max = max(n_observations), .groups = "drop")

.overall_panel <- expand_grid(countries, year = start_year:end_year) %>%
  left_join(.dv_counts_overall, by = c("geo_area_code", "geo_area_name", "year")) %>%
  mutate(across(all_of(.count_cols), ~ coalesce(.x, 0L))) %>%
  left_join(.baseline_overall, by = c("geo_area_code", "geo_area_name")) %>%
  mutate(goal_baseline_all = .gb_overall_all, goal_baseline_stable = .gb_overall_stable) %>%
  left_join(.frontier_overall, by = "year") %>%
  .add_dv_ratios() %>%
  mutate(goal = NA_integer_, scope = "overall")

# Stack. `scope` distinguishes the two; goal is 1-17 on goal rows, NA on overall.
goal_lvl_dv_data <- bind_rows(.goal_panel, .overall_panel) %>%
  select(-baseline_mean_all, -baseline_mean_stable,
         -goal_baseline_all, -goal_baseline_stable, -frontier_max) %>%
  select(geo_area_code, geo_area_name, iso3, year, scope, goal, everything()) %>%
  arrange(geo_area_name, year, scope, goal)

# Variable labels (attr "label") documenting the series universe behind each
# count column — in particular the series COUNT feeding the all-series vs
# stable-core columns, computed live so they never go stale. readr::write_csv
# drops attributes, so these survive only in the .rds twin written below (and
# in-session, e.g. RStudio's viewer / Hmisc / labelled / gtsummary).
attr(goal_lvl_dv_data$scope, "label") <-
  "goal = one row per country-year-goal (goal 1-17); overall = per country-year (goal NA)"
attr(goal_lvl_dv_data$n_observations, "label") <-
  sprintf("Observation count — all %d series", agg_series_total)
attr(goal_lvl_dv_data$n_observations_country, "label") <-
  "Observation count — country-produced only (nature C/CA)"
attr(goal_lvl_dv_data$n_observations_agency, "label") <-
  "Observation count — agency-produced only (nature E/M/G)"
attr(goal_lvl_dv_data$n_declared_missing, "label") <-
  "Rows the UN opened for this country-goal-year and left empty (value was NaN)"
attr(goal_lvl_dv_data$n_missing_structural, "label") <-
  "Declared-missing: indicator not applicable (Nature N / Obs Status M)"
attr(goal_lvl_dv_data$n_missing_suppressed, "label") <-
  "Declared-missing: withheld (Obs Status Q)"
attr(goal_lvl_dv_data$n_missing_unknown, "label") <-
  "Declared-missing: reason not recoverable (Obs Status O, or neither field populated)"
attr(goal_lvl_dv_data$n_observations_stable, "label") <-
  sprintf("Observation count — %d framework-stable series", length(stable_codes))
attr(goal_lvl_dv_data$dv_n_observations_pct_baseline, "label") <-
  "n_observations / THIS country's own mean for this goal in 2015-17 (all series). NA if that baseline is 0"
attr(goal_lvl_dv_data$dv_n_observations_stable_pct_baseline, "label") <-
  "n_observations_stable / THIS country's own mean for this goal in 2015-17 (stable core). NA if that baseline is 0"
attr(goal_lvl_dv_data$dv_n_observations_pct_goalbase, "label") <-
  "n_observations / mean across ALL countries for this goal in 2015-17 (all series). Defined for every country-goal-year"
attr(goal_lvl_dv_data$dv_n_observations_stable_pct_goalbase, "label") <-
  "n_observations_stable / mean across ALL countries for this goal in 2015-17 (stable core). Defined for every country-goal-year"
attr(goal_lvl_dv_data$dv_n_observations_pct_frontier, "label") <-
  "vs TOP reporter: n_observations / goal-year max (all series). Denominator moves yearly"

write_csv(
  goal_lvl_dv_data,
  file.path(output_folder, "goal_lvl_dv_data.csv")
)
# .rds twin preserves the variable labels above (CSV cannot).
saveRDS(goal_lvl_dv_data, file.path(output_folder, "goal_lvl_dv_data.rds"))



# ---- 7. Series-code availability, both scopes: agg_series_counts_rc --------
# Counts SERIES CODES present, not observations: a series code counts once for
# a country-year no matter how many disaggregated observations sit under it.
# This is the coarser, SDR-style measure, kept for comparison.
#
# Two scopes stacked in one table, distinguished by `scope`:
#   scope == "goal"    — per country x year x goal; `goal` is filled, and the
#                        denominator is that goal's distinct series count.
#   scope == "overall" — per country x year; `goal` is NA, and the denominator
#                        is the framework-wide unique series count.
#
# The overall rows are NOT the sum of the goal rows: a series code appearing
# under two goals is counted once framework-wide but once per goal above, so
# both scopes are computed separately and stacked.
agg_series_counts_rc <- bind_rows(
  
  # -- goal scope --
  expand_grid(
      countries,
      year = start_year:end_year,
      goal = goals
    ) %>%
    left_join(
      agg_series_depth %>%
        group_by(geo_area_code, year, goal) %>%
        summarise(n_available_series         = sum(reported),
                  n_available_series_country = sum(reported_country),
                  # Series the UN treats as applicable here (`applicable` in agg_series_depth),
                  # i.e. excluding those flagged structurally non-relevant. An
                  # alternative, country-specific denominator.
                  n_applicable_series        = sum(applicable),
                  .groups = "drop"),
      by = c("geo_area_code", "year", "goal")
    ) %>%
    left_join(goal_totals, by = "goal") %>%
    transmute(
      geo_area_code, geo_area_name, iso3, year,
      scope = "goal",
      goal,
      n_available_series         = coalesce(n_available_series, 0L),
      n_available_series_country = coalesce(n_available_series_country, 0L),
      n_applicable_series        = coalesce(n_applicable_series, 0L),
      n_series_in_framework      = n_series_in_goal
    ),

  # -- overall scope --
  expand_grid(countries, year = start_year:end_year) %>%
    left_join(
      agg_series_depth %>%
        group_by(geo_area_code, geo_area_name, year, series_code) %>%
        summarise(rep = any(reported), rep_c = any(reported_country),
                  appl = any(applicable), .groups = "drop") %>%
        group_by(geo_area_code, geo_area_name, year) %>%
        summarise(n_available_series         = sum(rep),
                  n_available_series_country = sum(rep_c),
                  n_applicable_series        = sum(appl),
                  .groups = "drop"),
      by = c("geo_area_code", "geo_area_name", "year")
    ) %>%
    transmute(
      geo_area_code, geo_area_name, iso3, year,
      scope = "overall",
      goal  = NA_integer_,
      n_available_series         = coalesce(n_available_series, 0L),
      n_available_series_country = coalesce(n_available_series_country, 0L),
      n_applicable_series        = coalesce(n_applicable_series, 0L),
      n_series_in_framework      = agg_series_total
    )) %>%
  mutate(
    missing_series_count = n_series_in_framework - n_available_series,
    dv_availability_share   = n_available_series / n_series_in_framework,
    dv_missingness_share    = 1 - dv_availability_share
  ) %>%
  arrange(geo_area_name, year, scope, goal)

write_csv(
  agg_series_counts_rc,
  file.path(output_folder, "agg_series_counts_rc.csv"))


message("Count measures written to ", output_folder)
message("  goal_lvl_dv_data: ", nrow(goal_lvl_dv_data), " rows")
message("  agg_series_counts_rc: ", nrow(agg_series_counts_rc), " rows")
message("  stable-core series: ", length(stable_codes), " of ", agg_series_total)
