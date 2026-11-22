# ==============================================================================
# 02_clean_sdg.R -- make each column right.
#
# Step 2 of 5: 01 extract -> 02 clean -> 03 wrangle -> 04 select model series
#              -> 05 validate
#
# WHAT IT DOES
#   - Records WHY an empty cell is empty (missing_reason), then turns the UN's
#     "NaN" marker into a real missing value. The rows are KEPT: an empty cell
#     is part of what the index measures.
#   - Gives the columns consistent names (snake_case; TimePeriod -> year).
#   - Sorts the rows into a fixed order so every later output is reproducible.
#   Nothing is dropped here.
#
# INPUT   01_data/intermediate/sdg_extracted.rds   (from 01_extract_sdg.R)
# OUTPUT  01_data/intermediate/sdg_cleaned.rds     (read by 03_wrangle_sdg.R)
# ==============================================================================

library(here)
library(dplyr)
library(janitor)

input_file  <- here("01_data/intermediate/sdg_extracted.rds")
output_file <- here("01_data/intermediate/sdg_cleaned.rds")
if (!file.exists(input_file))
  stop(input_file, " not found. Run 02_processing/01_extract_sdg.R first.",
       call. = FALSE)

sdg <- readRDS(input_file)

# ---- 1. Why an empty cell is empty, then "NaN" -> NA ------------------------
# From the UN's Nature and Observation Status fields. Set only where the value
# is "NaN" (NA on cells that have a value), so is.na(value) and
# is.na(missing_reason) are opposites -- no separate flag is needed.
#   structural  Nature "N" or Observation Status "M": the indicator does not
#               apply here. NOT data loss. Nature "N" is the test because it
#               is the complete marker (some agencies tag only Nature).
#   suppressed  Observation Status "Q": withheld, usually confidential.
#   unknown     no reason given -- Observation Status "O", or neither field
#               populated (some agencies fill neither).
# Nature itself (who produced the value: C/CA country, E/M/G agency, N not
# relevant) is kept as it is; 03_wrangle_sdg.R summarises it.
sdg <- sdg %>%
  mutate(
    missing_reason = case_when(
      Value != "NaN"                                       ~ NA_character_,
      coalesce(Nature, "") == "N" |
        coalesce(`Observation Status`, "") == "M"          ~ "structural",
      coalesce(`Observation Status`, "") == "Q"            ~ "suppressed",
      TRUE                                                 ~ "unknown"
    ),
    # "NaN" means "no value", so convert it to a real NA. Reversible: Value is
    # NA exactly where missing_reason is set.
    Value = na_if(Value, "NaN")
  )

# ---- 2. Names and order ------------------------------------------------------
sdg_cleaned <- sdg %>%
  clean_names() %>%
  rename(year = time_period) %>%
  arrange(goal, geo_area_name, series_code, year, value, nature, observation_status)

# Labels documenting what an NA in `value` means, so the convention travels
# with the data. (CSV drops these; the .rds files keep them.)
attr(sdg_cleaned$value, "label") <-
  "Published value. NA = declared missing (\"NaN\" in the export); see missing_reason"
attr(sdg_cleaned$missing_reason, "label") <-
  "Why value is NA: structural / suppressed / unknown. NA where a value exists"

message("Declared-missing rows (value was \"NaN\" in the export):")
message("  ", format(sum(is.na(sdg_cleaned$value)), big.mark = ","),
        " of ", format(nrow(sdg_cleaned), big.mark = ","),
        sprintf(" (%.1f%%)", 100 * mean(is.na(sdg_cleaned$value))))
message("  by missing_reason:")
print(sdg_cleaned %>% filter(is.na(value)) %>%
        count(missing_reason, name = "rows") %>%
        mutate(pct = round(100 * rows / sum(rows), 1)) %>%
        arrange(desc(rows)))

saveRDS(sdg_cleaned, output_file)
message("\nwrote ", output_file)
