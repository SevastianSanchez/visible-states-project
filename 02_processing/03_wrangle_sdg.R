# ==============================================================================
# 03_wrangle_sdg.R -- make the table the right shape.
#
# Step 3 of 5: 01 extract -> 02 clean -> 03 wrangle -> 04 select model series
#              -> 05 validate
#
# WHAT IT DOES, in order
#   1-3  The rules for places: which are dropped, which roll up into a parent,
#        and the ISO3 codes the standard lookup cannot supply.
#   4    Rolls England & Wales, Scotland and Northern Ireland into the UK.
#   5    Drops the 60 non-sovereign places, and records each one and why.
#   6    Adds the ISO3 country code; stops if any place has none.
#        (After 4 and 5, because many dropped places have no ISO3 code.)
#        -> writes sdg_full_data.csv.gz, the cleaned rows for the 197 countries.
#   7    Series stability: when each series was first and last reported, and
#        whether it lasted the whole window. NOT used by the models; it feeds
#        the count measures (build_count_measures.R).
#   8    The series list: one row per series per goal, with its counts and
#        stability. -> writes series_stability_list.csv
#   9-10 One row per country, series and year: reported = 1 if at least one
#        value was published under any breakdown. Plus disaggregation depth
#        (for v3; not used by the models). -> writes agg_series_depth
#   11   The full grid: one row per country-year, one column per series,
#        absent = 0. -> writes grid_all_series.rds (1,773 x 665)
#
# INPUT   01_data/intermediate/sdg_cleaned.rds   (from 02_clean_sdg.R)
#         01_data/raw/un_sdg_exports/sdg_update_info.xlsx (section 7)
# OUTPUT  01_data/processed/sdg_full_data.csv.gz
#         01_data/processed/geo_exclusions.csv
#         01_data/processed/series_stability_list.csv
#         01_data/processed/agg_series_depth.csv.gz (+ .rds with labels)
#         01_data/processed/grid_all_series.rds
# ==============================================================================

library(here)
library(readxl)
library(dplyr)
library(purrr)
library(readr)
library(tidyr)
library(stringr)
library(janitor)
library(countrycode)
suppressPackageStartupMessages(library(data.table))  # section 11 only
source(here("rules.R"))

input_file    <- here("01_data/intermediate/sdg_cleaned.rds")
output_folder <- here("01_data/processed")
if (!file.exists(input_file))
  stop(input_file, " not found. Run 02_processing/01_extract_sdg.R and ",
       "02_clean_sdg.R first.", call. = FALSE)


# =============================================================================
# RULES FOR PLACES =============================================================
# =============================================================================

# ---- 1. Excluded geographies -------------------------------------------------
# M49 codes dropped from the country panel, grouped by reason. This one list
# drives both the filter (section 5) and the audit table (geo_exclusions.csv), so the
# record of what was removed cannot drift from what was actually removed.
#
# TO CHANGE THE PANEL: edit only this list. Each entry is "Geography name" = code;
# the group name becomes the `exclusion_reason`. The name is checked against the
# UN's published name in section 5, so a mistyped code is caught rather than silently
# dropping the wrong country.
#
# Excluded: places with no permanent population, "other areas" buckets, and
# states that no longer exist — none has a government or statistics office, so a
# reporting score for them says nothing about a government.
#
# NOT excluded on purpose:
#   - UK devolved jurisdictions (827/828/829): rolled up into the UK (section 2).
#   - Four non-members kept because they have their own statistics offices and
#     real data: 275 Palestine, 344 Hong Kong, 412 Kosovo, 446 Macao.
excluded_geographies <- list(
  "uninhabited or residual bucket" = c(
    "Antarctica"                                   =  10,
    "Bouvet Island"                                =  74,
    "British Indian Ocean Territory"               =  86,
    "Other non-specified areas in Eastern Asia"    = 158,
    "Christmas Island"                             = 162,
    "Cocos (Keeling) Islands"                      = 166,
    "South Georgia and the South Sandwich Islands" = 239,
    "French Southern Territories"                  = 260,
    "Heard Island and McDonald Islands"            = 334,
    "Norfolk Island"                               = 574,
    "United States Minor Outlying Islands"         = 581,
    "Pitcairn"                                     = 612,
    "Ascension"                                    = 655,
    "Sark"                                         = 680,
    "Svalbard and Jan Mayen Islands"               = 744
  ),

  # States that dissolved before the SDG era. M49 never retires a code — it
  # keeps them flagged "[former]" - Every row they carry in 2015-2023 is UNEP
  # material-flows model output (nature "E"), and 378 of the 379 values are
  # structural zeros. Successor states are all separately in the panel.
  "defunct entity" = c(
    "Yugoslavia [former]"            = 890,  # country no longer exists — SFRY dissolved 1992
    "Serbia and Montenegro [former]" = 891,  # country no longer exists — union dissolved June 2006
    "Netherlands Antilles  [former]" = 530   # country no longer exists — dissolved October 2010
  ),

  # Sub-national reporting strata whose parent state is separately in the panel.
  # THE RULE: the unit is the sovereign state, the government whose reporting
  # is scored. These strata are parts of a state that is scored in its own
  # right. Their parents are fully present — Tanzania (834) with 492
  # series, Iraq (368) with 437 — so nothing is lost from the panel.
  #
  # Corroborating, but NOT the criterion: both would also manufacture false data
  # loss if kept. A unit with 1-5 series scores near-zero availability because it
  # was never a reporting unit for 16 of 17 goals, not because reporting fell.
  # Zanzibar's 108 rows are 100% UNEP material-flows model zero-fill (nature E,
  # no country-reported observation at all); Central Iraq is a 5-series criminal
  # justice collection stratum with no Kurdistan counterpart to complete it.
  "sub-national reporting stratum" = c(
    "United Republic of Tanzania (Zanzibar)" = 836,  # region of Tanzania, not a state
    "Iraq (Central Iraq)"                    = 369   # survey stratum, not a state
  ),

  # Dependent territories and non-member entities. Same rule as the strata above:
  # the unit is the sovereign state, the government whose reporting is scored.
  #
  # NOT in this list, deliberately retained — see the note above the list:
  #   275 State of Palestine, 344 Hong Kong SAR, 446 Macao SAR, 412 Kosovo.
  "dependent territory or non-member" = c(
    "American Samoa"                   =  16,  # United States
    "Bermuda"                          =  60,  # United Kingdom
    "British Virgin Islands"           =  92,  # United Kingdom
    "Cayman Islands"                   = 136,  # United Kingdom
    "Mayotte"                          = 175,  # France
    "Cook Islands"                     = 184,  # New Zealand free association
    "Faroe Islands"                    = 234,  # Denmark
    "Falkland Islands (Malvinas)"      = 238,  # United Kingdom / disputed
    "Åland Islands"                    = 248,  # Finland
    "French Guiana"                    = 254,  # France
    "French Polynesia"                 = 258,  # France
    "Gibraltar"                        = 292,  # United Kingdom
    "Greenland"                        = 304,  # Denmark
    "Guadeloupe"                       = 312,  # France
    "Guam"                             = 316,  # United States
    "Holy See"                         = 336,  # UN observer, not a member
    "Martinique"                       = 474,  # France
    "Montserrat"                       = 500,  # United Kingdom
    "Curaçao"                          = 531,  # Netherlands
    "Aruba"                            = 533,  # Netherlands
    "Sint Maarten (Dutch part)"        = 534,  # Netherlands
    "Bonaire, Sint Eustatius and Saba" = 535,  # Netherlands
    "New Caledonia"                    = 540,  # France
    "Niue"                             = 570,  # New Zealand free association
    "Northern Mariana Islands"         = 580,  # United States
    "Puerto Rico"                      = 630,  # United States
    "Réunion"                          = 638,  # France
    "Saint Barthélemy"                 = 652,  # France
    "Saint Helena"                     = 654,  # United Kingdom
    "Anguilla"                         = 660,  # United Kingdom
    "Saint Martin (French Part)"       = 663,  # France
    "Saint Pierre and Miquelon"        = 666,  # France
    "Western Sahara"                   = 732,  # disputed territory
    "Tokelau"                          = 772,  # New Zealand
    "Turks and Caicos Islands"         = 796,  # United Kingdom
    "Guernsey"                         = 831,  # UK crown dependency
    "Jersey"                           = 832,  # UK crown dependency
    "Isle of Man"                      = 833,  # UK crown dependency
    "United States Virgin Islands"     = 850,  # United States
    "Wallis and Futuna Islands"        = 876   # France
  )
)

# Flatten to one row per excluded geography. geo_area_code is character in
# raw_data, so the codes are coerced here once rather than at every comparison.
# `geo_area_name_expected` is the name as configured above; section 5 checks it against
# the name the UN actually publishes for that code.
excluded_geo_reasons <- imap_dfr(excluded_geographies, function(codes, reason) {
  tibble(
    geo_area_code          = as.character(codes),
    geo_area_name_expected = names(codes),
    exclusion_reason       = reason)
})

excluded_geo_codes <- excluded_geo_reasons$geo_area_code

# Config integrity: every entry needs a name, and no code may appear twice.
.unnamed <- is.na(excluded_geo_reasons$geo_area_name_expected) |
            excluded_geo_reasons$geo_area_name_expected == ""
if (any(.unnamed)) {
  stop("Every entry in excluded_geographies must be written as ",
       "\"Geography name\" = code. Unnamed code(s): ",
       paste(excluded_geo_codes[.unnamed], collapse = ", "), call. = FALSE)
}
rm(.unnamed)

if (anyDuplicated(excluded_geo_codes) > 0) {
  stop("excluded_geographies lists the same geo_area_code more than once: ",
       paste(unique(excluded_geo_codes[duplicated(excluded_geo_codes)]),
             collapse = ", "), call. = FALSE)
}


# ---- 2. Sub-national roll-ups ------------------------------------------------
# Some countries report certain SDG series only at a sub-national jurisdiction,
# because the underlying institution is devolved. The UK is the case here: it
# has three separate legal systems, so UNODC publishes crime statistics per
# jurisdiction (England & Wales, Scotland, Northern Ireland) instead of one
# UK-wide figure. Those jurisdictions are not sovereign states, so they
# cannot be their own panel unit — but the data is
# real, country-produced reporting (nature "C") that the UK genuinely did, and
# 12 of the 14 series appear under no other UK code. Excluding them (as with the
# strata above) would understate UK Goal 16 reporting, so instead their rows are
# reassigned to the parent state and counted there. section 4 does the move.
#
# Each entry is "Child name" = child_code; `= <parent_code>` names the target.
# To roll a different country's sub-units up, add a block with its parent code.
rollup_to_parent <- list(
  "826" = c(  # -> United Kingdom of Great Britain and Northern Ireland
    "United Kingdom (England and Wales)" = 827,
    "United Kingdom (Northern Ireland)"  = 828,
    "United Kingdom (Scotland)"          = 829))

# Flatten to a child_code -> parent_code lookup used by section 4.
rollup_map <- imap_dfr(rollup_to_parent, function(children, parent) {
  tibble(
    child_code  = as.character(children),
    child_name  = names(children),
    parent_code = parent)
})

if (any(is.na(rollup_map$child_name) | rollup_map$child_name == "")) {
  stop("Every entry in rollup_to_parent must be written as ",
       "\"Child name\" = code.", call. = FALSE)
}
if (anyDuplicated(rollup_map$child_code) > 0) {
  stop("rollup_to_parent lists the same child code more than once: ",
       paste(unique(rollup_map$child_code[duplicated(rollup_map$child_code)]),
             collapse = ", "), call. = FALSE)
}
# A child cannot be both rolled up and excluded — that is a config contradiction.
.rollup_excluded <- intersect(rollup_map$child_code, excluded_geo_codes)
if (length(.rollup_excluded) > 0) {
  stop("These codes are in BOTH excluded_geographies and rollup_to_parent: ",
       paste(.rollup_excluded, collapse = ", "),
       ". A geography is either dropped or rolled up, not both.", call. = FALSE)
}
rm(.rollup_excluded)


# ---- 3. ISO3 merge key overrides ---------------------------------------------
# section 6 maps M49 geo_area_code -> ISO3 with countrycode(origin = "un"),
# which resolves 196 of the 197 retained geographies on its own. This list
# supplies ISO3 for the ones it cannot, and would also be the place to force a
# different code if the analysis needed one.
#
# ISO3 is the key every output uses, and the one the comparison data (World
# Bank income and GDP, SPI, HRV) merge on.
#
# Entries are "M49 code" = "ISO3".
iso3_overrides <- c(
  "412" = "XKX"   # Kosovo — no official M49 or ISO3 code exists; XKX is the
                  # de facto standard (World Bank, IMF, Eurostat).
)



# =============================================================================
# THE ROWS =====================================================================
# =============================================================================
raw_data <- readRDS(input_file)


# ---- 4. Sub-national roll-ups → raw_data ----------------------------------
# Reassign the sub-national jurisdictions configured in section 2 to their parent
# state, so their reporting counts under the sovereign unit the analysis uses.
# Runs before everything downstream (stability, panels) so they all see the
# rolled-up parent. See section 2 for the rationale.
#
# Collision handling: a child observation whose full disaggregation key already
# exists under the REAL parent is a component of a figure the parent already
# publishes as an aggregate (e.g. UNODC's UK homicide total = sum of the three
# legal jurisdictions). Keeping both would double-count, so the parent's own row
# wins and the child component is dropped. Child observations with no matching
# parent key are series the parent does not otherwise report; they move across
# and become the parent's data. The comparison key deliberately EXCLUDES
# geo_area_code, so it is parent-vs-child on the same series/year/disaggregation
# — NOT against other countries that report the same series.
if (nrow(rollup_map) > 0) {

  # Identifying key: everything that distinguishes an observation except the
  # geography, the value, and provenance (source / footnote). The separator is
  # a string that cannot occur inside these plain-text fields.
  .sep      <- "|~|"
  .key_cols <- setdiff(names(raw_data),
                       c("geo_area_code", "geo_area_name", "value",
                         "source", "foot_note"))
  .key      <- do.call(paste, c(raw_data[.key_cols], sep = .sep))

  .child_of  <- setNames(rollup_map$parent_code, rollup_map$child_code)
  .is_child  <- raw_data$geo_area_code %in% rollup_map$child_code
  .parents   <- unique(rollup_map$parent_code)

  # Keys each parent already carries, tagged by parent code, and the key each
  # child would land on under its parent. A child collides iff its target is in
  # the parent set.
  .is_parent      <- raw_data$geo_area_code %in% .parents
  .parent_key_set <- unique(paste(raw_data$geo_area_code[.is_parent],
                                  .key[.is_parent], sep = .sep))
  .child_target   <- paste(.child_of[raw_data$geo_area_code[.is_child]],
                           .key[.is_child], sep = .sep)

  .drop_row            <- logical(nrow(raw_data))
  .drop_row[.is_child] <- .child_target %in% .parent_key_set

  # A configured child code absent from the data does nothing silently — warn,
  # the same way section 5 warns about an unmatched exclusion code.
  .child_missing <- setdiff(rollup_map$child_code, raw_data$geo_area_code)
  if (length(.child_missing) > 0) {
    warning("rollup_to_parent lists ", length(.child_missing),
            " child code(s) not present in the data: ",
            paste(.child_missing, collapse = ", "),
            "\nCheck for a typo, or drop them from the list in section 2.")
  }

  # Per-child audit (captured BEFORE the move). Same schema as the exclusion
  # audit in section 5, so the two stack into one geo_exclusions.csv there.
  #   n_observations : rows the child contributed
  #   n_obs_retained : of those, how many were reassigned to the parent
  #                    (n_observations - n_obs_retained = duplicate components
  #                    dropped because the parent already published the aggregate)
  geo_rollup_audit <- raw_data %>%
    filter(.is_child) %>%
    mutate(.dropped = .drop_row[.is_child]) %>%
    group_by(geo_area_code, geo_area_name) %>%
    summarise(
      n_observations = n(),
      n_obs_retained = sum(!.dropped),
      n_series       = n_distinct(series_code),
      n_years        = n_distinct(year),
      first_year     = min(year),
      last_year      = max(year),
      .groups = "drop"
    ) %>%
    left_join(rollup_map, by = c("geo_area_code" = "child_code")) %>%
    transmute(
      geo_area_code, geo_area_name,
      disposition = "rolled up",
      reason      = paste0("devolved jurisdiction -> parent ", parent_code),
      parent_code,
      n_observations, n_obs_retained, n_series, n_years, first_year, last_year
    )

  # Names for the reassigned rows: pull each parent's canonical name from its
  # own rows in the data.
  .parent_names <- raw_data %>%
    filter(geo_area_code %in% .parents) %>%
    distinct(geo_area_code, geo_area_name) %>%
    { setNames(.$geo_area_name, .$geo_area_code) }

  .uk_series_before <- n_distinct(
    raw_data$series_code[raw_data$geo_area_code %in% .parents])

  # Drop colliding components, then reassign the survivors to their parent.
  raw_data  <- raw_data[!.drop_row, ]
  .moved    <- raw_data$geo_area_code %in% rollup_map$child_code
  .new_par  <- unname(.child_of[raw_data$geo_area_code[.moved]])
  raw_data$geo_area_name[.moved] <- .parent_names[.new_par]
  raw_data$geo_area_code[.moved] <- .new_par

  .uk_series_after <- n_distinct(
    raw_data$series_code[raw_data$geo_area_code %in% .parents])

  message("\nSub-national roll-ups (see section 2; logged in geo_exclusions.csv):")
  message("  children rolled up: ", nrow(geo_rollup_audit),
          " into ", length(.parents), " parent(s)")
  message("  rows moved: ", sum(geo_rollup_audit$n_obs_retained),
          " | rows dropped as duplicate components: ",
          sum(geo_rollup_audit$n_observations - geo_rollup_audit$n_obs_retained))
  message("  parent series before -> after: ",
          .uk_series_before, " -> ", .uk_series_after,
          " (+", .uk_series_after - .uk_series_before, ")")

  rm(.sep, .key_cols, .key, .child_of, .is_child, .parents, .is_parent,
     .parent_key_set, .child_target, .drop_row, .child_missing, .parent_names,
     .moved, .new_par, .uk_series_before, .uk_series_after)
}


# ---- 5. Geography exclusions → geo_exclusions ------------------------------
# Drop the geographies configured in section 1, and write ONE audit table (also
# carrying the section 4 roll-ups) of every geography that left its own code — whether
# excluded outright or reassigned to a parent. The `disposition` column says
# which. Driven by the same config that drives the actions, so the CSV is a
# report of what happened, not a hand-maintained list that can fall out of sync.
#
# Built BEFORE the exclusion filter runs, so it carries the real observation and
# series counts each excluded geography contributed. Schema matches the section 4
# roll-up audit so the two stack:
#   disposition    "excluded" | "rolled up"
#   reason         exclusion reason group, or the roll-up target
#   parent_code    the parent a rolled-up child went to (NA for excluded)
#   n_observations rows the geography contributed
#   n_obs_retained rows kept (0 for excluded; reassigned rows for rolled up)
excluded_audit <- raw_data %>%
  filter(geo_area_code %in% excluded_geo_codes) %>%
  group_by(geo_area_code, geo_area_name) %>%
  summarise(
    n_observations = n(),
    n_series       = n_distinct(series_code),
    n_years        = n_distinct(year),
    first_year     = min(year),
    last_year      = max(year),
    .groups = "drop"
  ) %>%
  right_join(excluded_geo_reasons, by = "geo_area_code") %>%
  mutate(across(c(n_observations, n_series, n_years), ~ coalesce(.x, 0L)),
    # `geo_area_name` is authoritative when the code matched; fall back to the
    # configured name so an unmatched code is still readable in the report.
    name_matches_config = !is.na(geo_area_name) &
                          geo_area_name == geo_area_name_expected,
    geo_area_name       = coalesce(geo_area_name, geo_area_name_expected))

# A configured code that matched nothing is worth knowing about: it is either a
# typo, or a geography the UN no longer publishes. Not fatal — just reported.
unmatched_geo <- excluded_audit %>% filter(n_observations == 0)
if (nrow(unmatched_geo) > 0) {
  warning("excluded_geographies lists ", nrow(unmatched_geo),
          " code(s) not present in the data: ",
          paste0(unmatched_geo$geo_area_code, " (",
                 unmatched_geo$geo_area_name_expected, ")", collapse = ", "),
          "\nCheck for a typo, or drop them from the list in section 1.")
}

# A code that matched a DIFFERENT geography than the config claims means the
# wrong country is being excluded. That is worth shouting about.
mismatched_geo <- excluded_audit %>%
  filter(n_observations > 0, !name_matches_config)
if (nrow(mismatched_geo) > 0) {
  warning("excluded_geographies names do not match the UN's published names ",
          "for these codes — the WRONG geography may be excluded:\n",
          paste0("  code ", mismatched_geo$geo_area_code,
                 ": configured as '", mismatched_geo$geo_area_name_expected,
                 "', data says '", mismatched_geo$geo_area_name, "'",
                 collapse = "\n"))
}

# One audit table: exclusions + roll-ups (section 4), in the shared schema.
geo_exclusions <- bind_rows(
  excluded_audit %>%
    transmute(
      geo_area_code, geo_area_name,
      disposition = "excluded",
      reason      = exclusion_reason,
      parent_code = NA_character_,
      n_observations, n_obs_retained = 0L,
      n_series, n_years, first_year, last_year),
    if (exists("geo_rollup_audit")) geo_rollup_audit) %>%
  arrange(disposition, reason, as.integer(geo_area_code))

write_csv(geo_exclusions, file.path(output_folder, "geo_exclusions.csv"))

n_before   <- nrow(raw_data)
raw_data   <- raw_data %>% filter(!geo_area_code %in% excluded_geo_codes)
n_excluded <- n_before - nrow(raw_data)

message("\nGeography exclusions (see section 1; logged in geo_exclusions.csv):")
message("  configured codes: ", length(excluded_geo_codes),
        " across ", length(excluded_geographies), " reason group(s)")
message("  matched in data:  ", sum(excluded_audit$n_observations > 0))
message("  observations removed: ", format(n_excluded, big.mark = ","),
        sprintf(" (%.2f%% of %s)", 100 * n_excluded / n_before,
                format(n_before, big.mark = ",")))
message("  geographies retained: ", n_distinct(raw_data$geo_area_code))
print(geo_exclusions %>% select(geo_area_code, geo_area_name, disposition,
                               reason, n_observations, n_obs_retained, n_series))


# ---- 6. ISO3 merge key → raw_data$iso3 -------------------------------------
# Attach the analysis merge key here, at the point where the geography set is
# FINAL — after the roll-ups (section 4) and the exclusions (section 5), before raw_data is
# written. Everything downstream inherits it, and the mapping is validated in
# the same place the geography decisions are reported.
#
# The SDG exports carry M49 numeric codes only; every output keys on ISO3.
# countrycode(origin = "un") is a direct code-to-code lookup, so this avoids
# name matching entirely — no "Türkiye" vs "Turkey" or "Viet Nam" vs "Vietnam".
# section 3 supplies ISO3 for codes the lookup cannot resolve.
raw_data <- raw_data %>%
  mutate(
    iso3 = suppressWarnings(
      countrycode(as.integer(geo_area_code), origin = "un", destination = "iso3c")),
    iso3 = coalesce(unname(iso3_overrides[geo_area_code]), iso3)
  )

.geo_iso <- raw_data %>% distinct(geo_area_code, geo_area_name, iso3)

# Any geography left without an ISO3 cannot be merged to other datasets, and
# downstream it would become a country with a missing key (the model grid
# is keyed on iso3). So this stops the run rather than warning.
.iso_missing <- .geo_iso %>% filter(is.na(iso3))
if (nrow(.iso_missing) > 0) {
  stop("No ISO3 for ", nrow(.iso_missing), " geography(ies): ",
       paste0(.iso_missing$geo_area_code, " (", .iso_missing$geo_area_name, ")",
              collapse = ", "),
       "\nAdd them to iso3_overrides in section 3, or exclude them in section 1.",
       call. = FALSE)
}

# Two geographies sharing an ISO3 would fan out rows on the join.
.iso_dupes <- .geo_iso %>% filter(!is.na(iso3)) %>% count(iso3) %>% filter(n > 1)
if (nrow(.iso_dupes) > 0) {
  stop("Duplicate ISO3 across geographies: ",
       paste(.iso_dupes$iso3, collapse = ", "),
       ". The merge would duplicate rows.", call. = FALSE)
}

message("\nISO3 merge key (see sections 3 and 6):")
message("  geographies: ", nrow(.geo_iso),
        " | resolved: ", sum(!is.na(.geo_iso$iso3)),
        " | via override: ", sum(.geo_iso$geo_area_code %in% names(iso3_overrides)),
        " | unresolved: ", nrow(.iso_missing))
rm(.geo_iso, .iso_missing, .iso_dupes)

write_csv(raw_data, file.path(output_folder, "sdg_full_data.csv.gz"))


# ---- 7. Series stability → series_stability ----------------------------------
# NOT used by the models. It feeds the count measures (build_count_measures.R).
#
# The SDG framework grew inside the study window (483 series with country data
# in 2015 -> 565 in 2022), so a raw observation count drifts upward for reasons
# that have nothing to do with country behaviour. A series is "structurally
# available" in a year if at least one country published a value for it that
# year; the stable core is the series available in EVERY year of core_window.
#
# Derived from the data, not from the UN update log: the log only starts in
# June 2018, 82% of its rows say "Data updated.", and it records when the
# DATABASE ingested a series, not when the FRAMEWORK gained it (254 series are
# logged as "added" but have data back to 2015). The log's dates are joined on
# as supporting evidence only.
#
# core_window is kept apart from start_year:end_year because the two answer
# different questions ("which years must a series span to count as stable" vs
# "which years are analysed"). They coincide today; the guard catches it if
# they ever stop coinciding.
core_window            <- 2015:2023
stability_updates_path <- here("01_data/raw/un_sdg_exports/sdg_update_info.xlsx")

local({
  data_years <- range(raw_data$year, na.rm = TRUE)
  if (min(core_window) < data_years[1] || max(core_window) > data_years[2]) {
    stop("core_window (", min(core_window), "-", max(core_window),
         ") is not covered by the data (", data_years[1], "-", data_years[2], ").\n",
         "No series can be present in every core year, so stable_codes would be ",
         "empty. Narrow core_window in section 7.", call. = FALSE)
  }
})

# Only PUBLISHED values make a series "live" in a year; a declared-missing row
# is the UN opening a slot and finding nothing.
.live <- raw_data %>% filter(!is.na(value))

series_year <- .live %>%
  group_by(series_code, year) %>%
  summarise(n_countries = n_distinct(geo_area_code), n_obs = n(), .groups = "drop")

lifespan <- series_year %>%
  group_by(series_code) %>%
  summarise(
    first_year    = min(year),
    last_year     = max(year),
    n_years_live  = n_distinct(year),
    total_obs     = sum(n_obs),
    max_countries = max(n_countries),
    .groups = "drop"
  )

stable_codes <- series_year %>%
  filter(year %in% core_window) %>%
  distinct(series_code, year) %>%
  count(series_code) %>%
  filter(n == length(core_window)) %>%
  pull(series_code)

# Two independent flags, because a series can do BOTH (start after the window
# opens AND stop before it closes). Filter on these, not on `status`, which is
# a mutually exclusive summary: a series that starts late and ends early is
# filed under "entered_late" only.
series_stability <- lifespan %>%
  mutate(
    is_stable_core = series_code %in% stable_codes,
    starts_late    = first_year > min(core_window),
    ends_early     = last_year  < max(core_window),
    status = case_when(
      is_stable_core ~ "stable",
      starts_late    ~ "entered_late",
      ends_early     ~ "exited_early",
      TRUE           ~ "intermittent"
    )
  )

if (file.exists(stability_updates_path)) {
  series_stability <- series_stability %>%
    left_join(
      read_excel(stability_updates_path, sheet = "Data Updates") %>%
        clean_names() %>%
        filter(!is.na(series_code)) %>%
        mutate(date = as.Date(date), note = str_to_lower(as.character(action_notes))) %>%
        group_by(series_code = as.character(series_code)) %>%
        summarise(
          log_first_seen   = min(date, na.rm = TRUE),
          log_added_date   = suppressWarnings(min(date[str_detect(note, "series added|added to the database")], na.rm = TRUE)),
          log_removed_date = suppressWarnings(max(date[str_detect(note, "series deleted|series removed")], na.rm = TRUE)),
          n_log_events     = n(),
          .groups = "drop"
        ) %>%
        mutate(across(c(log_added_date, log_removed_date),
                      ~ if_else(is.infinite(as.numeric(.x)), as.Date(NA), .x))),
      by = "series_code"
    )
} else {
  stop("UN update log not found at ", stability_updates_path, call. = FALSE)
}

message("\nSeries stability (section 7):")
message("  stable-core series: ", length(stable_codes), " of ", nrow(series_stability),
        " (", round(100 * length(stable_codes) / nrow(series_stability)), "%)")
message("  discontinued (ends_early): ", sum(series_stability$ends_early))
message("  series with any country data, by year:")
print(as.data.frame(series_year %>% distinct(series_code, year) %>%
                      count(year, name = "n_series_live") %>% arrange(year)))
rm(.live)


# ---- 8. Series list with stability → series_stability_list -------------------
# One row per goal-target-indicator-series: a series under two goals has two
# rows. The models read series_code and goal from it (to assign each series a
# goal); the counts and stability columns are for reference.
#
# Stability columns come from section 7. total_obs is not repeated: it equals
# n_observations for every series.
series_stability_list <- raw_data %>%
  distinct(goal, target, indicator, series_code, series_description) %>%
  left_join(series_stability %>%
              select(series_code, first_year, last_year, n_years_live,
             is_stable_core, starts_late, ends_early, status),
    by = "series_code") %>%
  # One pass: each column counts the rows meeting its own condition.
  # pct_country_produced says how much of a series is the country's own
  # reporting versus a custodian agency's estimate.
  left_join(
    raw_data %>%
      group_by(series_code) %>%
      summarise(
        n_observations      = sum(!is.na(value)),
        n_observations_country = sum(!is.na(value) & nature %in% c("C", "CA")),
        n_observations_agency  = sum(!is.na(value) & nature %in% c("E", "M", "G")),
        n_declared_missing  = sum(is.na(value)),
        n_missing_structural = sum(is.na(value) & missing_reason == "structural"),
        n_missing_suppressed = sum(is.na(value) & missing_reason == "suppressed"),
        .groups = "drop"
      ) %>%
      mutate(pct_country_produced = if_else(n_observations > 0,
               round(100 * n_observations_country / n_observations, 1), NA_real_)),
    by = "series_code") %>%
  mutate(across(c(n_observations, n_observations_country, n_observations_agency,
                  n_declared_missing, n_missing_structural, n_missing_suppressed),
                ~ coalesce(.x, 0L))) %>%
  left_join(series_stability %>%
              select(series_code, max_countries, log_first_seen, log_added_date,
                     log_removed_date, n_log_events),
    by = "series_code") %>%
  arrange(goal, target, indicator, series_code)

write_csv(series_stability_list, file.path(output_folder, "series_stability_list.csv"))


# =============================================================================
# REPORTED, PER COUNTRY, SERIES AND YEAR =======================================
# =============================================================================

# ---- 9. Series-code presence and depth: agg_series_depth -------------------
# One row per country x series-code x year with any published value. Two
# summary columns preserve the disaggregation shape for later analysis:
#   nature_codes   — "/"-joined sorted unique natures (e.g., "C/M"), so shifts
#                    in provenance mix stay visible.
#   n_disagg_rows  — count of raw observations feeding this row, so drops in
#                    disaggregation depth are visible even when presence is
#                    unchanged.
# Also the input to build_count_measures.R's series-code counts.
#   n_declared_missing — slots the UN opened here and left empty.
#   reported           — TRUE if at least one published value exists. A cell
#                        that is ALL declared-missing is NOT reported, and build_count_measures.R
#                        must not count it as an available series.
agg_series_depth <- raw_data %>%
  group_by(goal, geo_area_code, geo_area_name, iso3, year, series_code) %>%
  summarise(
    nature_codes       = na_if(paste(sort(unique(nature[!is.na(value)])),
                                     collapse = "/"), ""),
    n_disagg_rows      = sum(!is.na(value)),
    n_country_rows     = sum(!is.na(value) & nature %in% c("C", "CA")),
    n_agency_rows      = sum(!is.na(value) & nature %in% c("E", "M", "G")),
    n_declared_missing = sum(is.na(value)),
    # Split of n_declared_missing by missing_reason (02_clean_sdg.R). `applicable` is the
    # useful one: TRUE unless every empty row here is structural non-relevance,
    # i.e. the series genuinely does not apply to this country-year.
    n_missing_structural  = sum(is.na(value) & missing_reason == "structural"),
    n_missing_suppressed  = sum(is.na(value) & missing_reason == "suppressed"),
    reported           = any(!is.na(value)),
    reported_country   = any(!is.na(value) & nature %in% c("C", "CA")),
    applicable         = any(!is.na(value) | missing_reason != "structural"),
    .groups = "drop"
  ) %>%
  arrange(goal, geo_area_name, year, series_code)

# ---- 10. Disaggregation-depth denominators ---------------------------------
# n_disagg_rows says HOW MANY disaggregation combos a country reported for a
# series in a year. To compare that across countries it needs a per-series
# ceiling. Two are provided (identical for ~96% of series):
#
#   depth_frontier — the most any single country-year reported for the series.
#                    Demonstrably attainable (a real country hit it), so it is
#                    the PRIMARY denominator. dv_depth_pct_frontier is in [0, 1].
#   depth_union    — every distinct disaggregation combo (age x sex x location x
#                    units) ever seen for the series, pooled across all country-
#                    years. Wider, because it pools mutually exclusive survey
#                    designs (e.g. incompatible age bands), so no single country
#                    can reach it — a ROBUSTNESS ceiling only.
#
# Both are per-series constants. depth_union is floored at depth_frontier so it
# is never smaller than the largest single realization; this also handles series
# whose depth lives in a DROPPED specialty column (e.g. EN_REF_WASCOL is one row
# per city), where the age/sex/location/units combo count is 1 but n_disagg_rows
# is large — there, union falls back to the frontier.
depth_frontier <- agg_series_depth %>%
  group_by(series_code) %>%
  summarise(depth_frontier = max(n_disagg_rows), .groups = "drop")

depth_union <- raw_data %>%
  filter(!is.na(value)) %>%
  distinct(series_code, age, sex, location, units) %>%
  count(series_code, name = "depth_union_combos") %>%
  left_join(depth_frontier, by = "series_code") %>%
  transmute(series_code,
            depth_union = pmax(depth_union_combos, depth_frontier))

agg_series_depth <- agg_series_depth %>%
  left_join(depth_frontier, by = "series_code") %>%
  left_join(depth_union,    by = "series_code") %>%
  mutate(
    # Share of the series' demonstrated maximum depth this country reached here.
    dv_depth_pct_frontier = if_else(depth_frontier > 0,
                                 n_disagg_rows / depth_frontier, NA_real_),
    # Same, against the wider union ceiling (robustness).
    dv_depth_pct_union    = if_else(depth_union > 0,
                                 n_disagg_rows / depth_union, NA_real_)
  )

write_csv(
  agg_series_depth,
  file.path(output_folder, "agg_series_depth.csv.gz")
)
# .rds twin carries the column labels below (write_csv drops attributes).
attr(agg_series_depth$n_disagg_rows, "label") <-
  "Disaggregation combos this country reported for the series-year (published rows)"
attr(agg_series_depth$depth_frontier, "label") <-
  "Per-series ceiling: most any single country-year reported (attainable)"
attr(agg_series_depth$depth_union, "label") <-
  "Per-series ceiling: all combos ever seen for the series, pooled (robustness)"
attr(agg_series_depth$dv_depth_pct_frontier, "label") <-
  "n_disagg_rows / depth_frontier — share of attainable depth reached, in [0,1]"
attr(agg_series_depth$dv_depth_pct_union, "label") <-
  "n_disagg_rows / depth_union — share of the union ceiling reached, in [0,1]"
saveRDS(agg_series_depth, file.path(output_folder, "agg_series_depth.rds"))


# ---- 11. Full grid → grid_all_series ----------------------------------------
# One row per country-year, one column per series, 1 = reported that year.
# agg_series_depth holds only cells that exist in the UN export, so the grid has
# to be completed: a country-series-year with no row at all is 0, not missing.
# A series under several goals has one row per goal in agg_series_depth; it gets
# ONE column here (reported if reported under any of its goals).
depth <- as.data.table(agg_series_depth)[, .(iso3, series_code, year, reported)]
depth <- depth[, .(reported = any(reported)), by = .(iso3, series_code, year)]

grid <- CJ(iso3        = sort(unique(depth$iso3)),
           series_code = sort(unique(depth$series_code)),
           year        = sort(unique(depth$year)), unique = TRUE)

cells <- merge(grid, depth, by = c("iso3", "series_code", "year"), all.x = TRUE)
cells[, y := as.integer(!is.na(reported) & reported)]

# data.table::dcast is named explicitly so a masking dcast from another package
# can never be picked up instead.
grid_all_series <- data.table::dcast(cells, iso3 + year ~ series_code, value.var = "y")
saveRDS(grid_all_series, file.path(output_folder, "grid_all_series.rds"))

message("\nFull grid (section 11): ", nrow(grid_all_series), " country-years x ",
        ncol(grid_all_series) - 2L, " series = ",
        format(nrow(cells), big.mark = ","), " cells, ",
        sprintf("%.1f%%", 100 * mean(cells$y)), " reported")
message("done.")
