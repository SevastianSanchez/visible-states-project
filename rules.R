# ==============================================================================
# rules.R -- the fixed numbers the pipeline uses, written once.
#
# Sourced, never run. Every script that needs one of these numbers sources this
# file instead of typing the number itself, so two scripts can never disagree.
#
#   source(here::here("rules.R"))
#
# Changing a number here changes the index. Record why in METHODS_LOG.md first.
# ==============================================================================

# ---- Years -------------------------------------------------------------------
# The analysis window. Ends at 2023, not 2025, because the UN has not finished
# filling in the recent years (2024 has ~85% of a normal year's observations,
# 2025 only ~20%). Extend this once the UN backfills.
start_year <- 2015L
end_year   <- 2023L

# ---- Which series the models use ---------------------------------------------
# A series is dropped if it is reported in 2% or less, or 98% or more, of the
# 1,773 country-years. A series nearly every country reports, or nearly none
# does, tells the model almost nothing about who reports more.
item_lo <- 0.02
item_hi <- 0.98

# ---- Goals -------------------------------------------------------------------
# A goal needs at least this many series to be scored on its own. Below it the
# goal's factor is not identified. Goal 7 has 3 series, so it gets no goal score
# in either layer; its series still count toward the overall index.
min_series_per_goal <- 10L

# Goals withheld from release on CONTENT grounds, not precision: goal 6 is
# mostly agency-produced, and a third of goal 15's series are treaty and policy
# instruments, which may track commitment rather than reporting effort.
goals_held <- c(6L, 15L)
