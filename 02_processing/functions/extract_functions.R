# ==============================================================================
# extract_functions.R -- functions used by 01_extract_sdg.R.
#
# Sourced, never run. Functions take inputs and return results; they do not
# know where files live. The script passes them the file path and the rules.
# ==============================================================================

# Stops the run if any check flags a row, naming each failed check, how many
# rows it caught, and up to five example rows. `checks` is a named list of
# logical vectors (TRUE = malformed), one per reason.
stop_if_malformed <- function(rows, file_path, checks) {
  failed <- Filter(any, checks)
  if (length(failed) == 0) return(invisible(NULL))
  for (reason in names(failed)) {
    message("\n", basename(file_path), ": ", sum(failed[[reason]]),
            " row(s) where ", reason, ". Examples:")
    print(rows[failed[[reason]], c("SeriesCode", "GeoAreaCode", "GeoAreaName",
                                   "TimePeriod", "Value")], n = 5)
  }
  stop(basename(file_path), " has malformed rows:\n",
       paste0("  - ", sapply(failed, sum), " row(s) where ", names(failed),
              collapse = "\n"),
       "\nExamples are printed above. Inspect the export before going further.",
       call. = FALSE)
}

# Reads one UN goal export: only the columns in `keep_columns`, only the years
# start_year to end_year, and no world or regional totals. Stops on malformed
# rows instead of dropping them. Everything comes in as text except TimePeriod
# and Goal, which become integers.
read_goal_file <- function(file_path, keep_columns, start_year, end_year,
                           aggregate_geographies) {
  message("Reading: ", basename(file_path))

  # Read column names first so the run fails loudly if an export's schema
  # has drifted, instead of silently dropping variables.
  file_columns    <- names(readxl::read_excel(file_path, n_max = 0))
  missing_columns <- setdiff(keep_columns, file_columns)

  if (length(missing_columns) > 0) {
    warning(basename(file_path), " is missing: ",
            paste(missing_columns, collapse = ", "),
            "\nThose fields will be created as NA.")
  }

  # Type each kept column as "text" and skip the rest, so the ~53 unneeded
  # columns are never parsed.
  columns_to_read  <- intersect(keep_columns, file_columns)
  col_types_vector <- ifelse(file_columns %in% columns_to_read, "text", "skip")
  goal_data        <- readxl::read_excel(file_path, col_types = col_types_vector)

  # Backfill absent requested columns as NA, then enforce a consistent order.
  for (column_name in setdiff(keep_columns, names(goal_data))) {
    goal_data[[column_name]] <- NA
  }

  goal_data <- goal_data %>% select(all_of(keep_columns))

  # Malformed rows stop the run instead of being dropped silently. They are
  # broken export rows, not reporting outcomes. A "NaN" Value is NOT malformed:
  # it is the UN declaring the slot empty, and it is kept as part of the
  # outcome (converted to NA in 02_clean_sdg.R).
  #
  # The year is checked on every row, before the window filter: a year that is
  # not a whole number cannot be placed inside or outside the window, and
  # as.integer() would turn it into NA and let the filter drop it unseen.
  stop_if_malformed(goal_data, file_path, list(
    "TimePeriod is blank or not a four-digit whole-number year (e.g. '2017n', '2017.5')" =
      !str_detect(coalesce(goal_data$TimePeriod, ""), "^[0-9]{4}$")
  ))

  goal_data <- goal_data %>%
    mutate(
      TimePeriod = as.integer(TimePeriod),
      Goal       = suppressWarnings(as.integer(Goal))
    ) %>%
    filter(
      TimePeriod >= start_year,
      TimePeriod <= end_year,
      !GeoAreaName %in% aggregate_geographies
    )

  # Value and area code are checked on the rows that are kept.
  stop_if_malformed(goal_data, file_path, list(
    "Value is blank: neither a published value nor the UN's \"NaN\" declared-missing marker" =
      coalesce(goal_data$Value, "") == "",
    "GeoAreaCode is blank or not a numeric M49 code" =
      !str_detect(coalesce(goal_data$GeoAreaCode, ""), "^[0-9]+$")
  ))

  # Sanity check: warn if two rows share every kept column. In well-formed
  # UN exports this is zero (any apparent duplicates come from dropped
  # specialty dimensions like Disability status, Cause of death, Type of
  # product, etc., which is exactly why no distinct() is ever called).
  n_dup <- sum(duplicated(goal_data))
  if (n_dup > 0) {
    warning(basename(file_path), " contains ", n_dup,
            " row(s) that duplicate on the kept columns after filtering — ",
            "these are legitimate observations distinguished by dropped ",
            "specialty disaggregation columns; inspect before trusting.")
  }
  goal_data
}
