# ==============================================================================
# 01_extract_sdg.R -- read the 17 UN SDG goal exports.
#
# Step 1 of 5 in building the data the models use:
#   01 extract -> 02 clean -> 03 wrangle -> 04 select model series -> 05 validate
#
# WHAT IT DOES
#   - Reads Goal1.xlsx ... Goal17.xlsx, keeping only the columns listed below.
#   - Keeps the years in rules.R (2015-2023) and drops world and regional
#     totals while reading.
#   - Stops, naming the reason, on any malformed row: a blank Value, an area
#     code that is not a number, or a year that is not a four-digit whole number.
#
# INPUT   01_data/raw/un_sdg_exports/Goal1.xlsx ... Goal17.xlsx
#         The exports are a fixed snapshot: downloaded Aug 16, 2026; database
#         last updated July 7, 2026. They are not on GitHub (310 MB); the README
#         says how to download them.
# OUTPUT  01_data/intermediate/sdg_extracted.rds (read by 02_clean_sdg.R; not
#         on GitHub, rebuilt by running this script)
# ==============================================================================

library(here)
library(readxl)
library(dplyr)
library(purrr)
library(stringr)
source(here("rules.R"))
source(here("02_processing/functions/extract_functions.R"))

input_folder <- here("01_data/raw/un_sdg_exports")
output_file  <- here("01_data/intermediate/sdg_extracted.rds")
dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)

# Only the fields needed for an auditable series-availability analysis.
keep_columns <- c(
  "Goal", "Target", "Indicator",
  "SeriesCode", "SeriesDescription",
  "GeoAreaCode", "GeoAreaName",
  "TimePeriod", "Value",
  "Source", "FootNote",
  "Age", "Location", "Nature", "Sex", "Units",
  "Observation Status"
)
# NOT kept, though present in the export schema -- both carry no information:
#   Freq            100% empty in all 17 files (the UN never populates it)
#   Reporting Type  a single constant value, "G", on every row

# GeoAreaName values that are world or regional totals, not reporting units.
aggregate_geographies <- c(
  "World", "Africa", "Asia", "Europe", "Oceania",
  "Northern Africa and Western Asia", "Central Asia and Southern Asia",
  "Eastern Asia and South-eastern Asia", "Latin America and the Caribbean",
  "Sub-Saharan Africa", "Europe and Northern America"
)

# ---- 1. Find the 17 exports --------------------------------------------------
if (!dir.exists(input_folder)) {
  stop("Input folder not found: ", input_folder,
       "\nCreate it and place Goal1.xlsx through Goal17.xlsx inside it.")
}

excel_files <- list.files(
  input_folder,
  pattern = "^Goal(0?[1-9]|1[0-7])\\.xlsx$",
  full.names = TRUE,
  ignore.case = TRUE)

if (length(excel_files) == 0) {
  stop("No files matching Goal1.xlsx ... Goal17.xlsx were found in ", input_folder)
}

# Order numerically so the log reads Goal1 ... Goal17, not Goal1, Goal10, ...
file_manifest <- tibble(file_path = excel_files) %>%
  mutate(file_name = basename(file_path),
         goal_from_file = as.integer(str_extract(file_name, "(?<=Goal)0?[0-9]+"))
  ) %>%
  arrange(goal_from_file)

message("Found ", nrow(file_manifest), " goal export files:")
print(file_manifest %>% select(file_name, goal_from_file))

if (nrow(file_manifest) != 17) {
  warning("Expected 17 files but found ", nrow(file_manifest),
          ". The script will run, but confirm no goal export is missing.")
}

# ---- 2. Read and combine -----------------------------------------------------
# No distinct() here or anywhere after: rows that look identical on the kept
# columns differ in dropped specialty columns (Disability status, Cause of
# death, Type of product, ...), and collapsing them would undercount.
sdg_extracted <- map_dfr(file_manifest$file_path, read_goal_file,
                         keep_columns = keep_columns,
                         start_year = start_year, end_year = end_year,
                         aggregate_geographies = aggregate_geographies)

saveRDS(sdg_extracted, output_file)
message("\nwrote ", output_file, " | ", format(nrow(sdg_extracted), big.mark = ","),
        " rows from ", nrow(file_manifest), " files")
