# ==============================================================================
# 04_select_model_series_sdg.R -- choose the series the models use.
#
# Step 4 of 5: 01 extract -> 02 clean -> 03 wrangle -> 04 select model series
#              -> 05 validate
#
# These rules exist for the models only. Descriptive work uses all 665 series
# in grid_all_series.rds and needs none of them.
#
# WHAT IT DOES, in order
#   1  Drops series reported in 2% or less, or 98% or more, of the 1,773
#      country-years (rules.R). A series nearly everyone or nearly no one
#      reports tells the model nothing.                              665 -> 607
#   2  Finds series that are the same measurement recorded twice (e.g. children
#      stunted as a % and in thousands) and keeps one per group, so a country
#      does not score twice for one reporting act.                   607 -> 524
#   3  Gives each series one goal. A series listed under several goals goes to
#      whichever of its own goals has the fewest series.
#
# THE DUPLICATE RULE (step 2) -- BOTH CONDITIONS MUST HOLD
#   (a) STRUCTURAL. The series' reported/not patterns are identical in every
#       country-year. No country has ever reported one without the other.
#   (b) SEMANTIC. They measure the same thing another way: their descriptions
#       share a stem once unit words are stripped. Same indicator and differing
#       units are supporting evidence, not requirements -- SH_DYN_IMRT and
#       SH_DYN_IMRTN span two indicators (3.2.1 and 3.2.2).
#   (a) alone is never enough: series reported by nearly every country-year
#   coincide trivially (forest certification, electricity access, GDP per capita
#   and refugee counts share one pattern at 99.5% reported). Comparison is
#   PAIRWISE within each identical-pattern group, so {forest %, forest hectares,
#   total land area} collapses the first two and leaves land area standing.
#   Groups that pass (a) but fail (b) are recorded as "keep_separate";
#   borderline similarity as "review". Neither is merged. Series are never
#   aggregated to UN indicator level.
#
# INPUT   01_data/processed/grid_all_series.rds      (from 03)
#         01_data/processed/series_stability_list.csv  (series -> goals, indicator)
#         01_data/processed/sdg_full_data.csv.gz            (descriptions and units)
# OUTPUT  01_data/processed/series_variant_map.csv     the duplicate groups and the evidence
#         01_data/processed/grid_model_series.rds    1,773 x 524, what the models fit
#         01_data/processed/grid_model_series.csv    the same grid as a CSV, for use without R
#         01_data/processed/series_goal.csv            each model series, its goals, its one goal
#         01_data/processed/filter_log.csv             series count after each rule
# ==============================================================================

source(here::here("packages.R"))
library(here)
suppressPackageStartupMessages(library(data.table))
source(here("rules.R"))
source(here("02_processing/functions/select_functions.R"))

msg <- function(...) cat(format(Sys.time(), "[%H:%M:%S] "), ..., "\n", sep = "")

sim_confirm <- 0.34   # description similarity at/above this = same measurement
sim_review  <- 0.20   # between the two = flagged for review, left separate

out_dir <- here("01_data/processed")
grid_all <- readRDS(file.path(out_dir, "grid_all_series.rds"))
msg("read grid_all_series: ", nrow(grid_all), " country-years x ",
    ncol(grid_all) - 2L, " series")

# ---- 1. THE 2-98% RULE -------------------------------------------------------
resp  <- as.data.frame(grid_all[, -(1:2)])
p_rep <- colMeans(resp)
keep  <- filter_prevalence(resp, item_lo, item_hi)
msg("1. 2-98% rule: ", ncol(resp), " -> ", sum(keep), " series")
resp  <- resp[, keep]

# ---- 2. DUPLICATE SERIES -----------------------------------------------------
M <- as.matrix(resp)

sl <- unique(fread(file.path(out_dir, "series_stability_list.csv"))[
  , .(series_code, indicator)])
sl <- sl[, .(indicator = paste(sort(unique(indicator)), collapse = ",")),
         by = series_code]
meta <- unique(fread(file.path(out_dir, "sdg_full_data.csv.gz"),
                     select = c("series_code", "series_description", "units")))
meta <- meta[, .SD[1], by = series_code]
info <- merge(data.table(series_code = colnames(M)), sl,   by = "series_code", all.x = TRUE)
info <- merge(info,                                 meta, by = "series_code", all.x = TRUE)

# Strip unit and quantifier words so only the phenomenon is compared. Without
# this, "Proportion of children stunted (%)" and "Children stunted (thousands)"
# look less alike than they are.
norm_desc <- function(x) {
  x <- tolower(as.character(x))
  x <- gsub("\\(.*?\\)", " ", x)
  x <- gsub(paste0("\\b(proportion|percentage|percent|number|total|share|rate|",
                   "per|of|the|in|and|capita|thousands|millions|index)\\b"), " ", x)
  x <- gsub("[^a-z ]", " ", x)
  trimws(gsub("\\s+", " ", x))
}
info[, ndesc := norm_desc(series_description)]

jacc <- function(a, b) {
  A <- unique(strsplit(a, " ")[[1]]); B <- unique(strsplit(b, " ")[[1]])
  A <- A[nchar(A) > 2]; B <- B[nchar(B) > 2]
  if (!length(A) || !length(B)) return(0)
  length(intersect(A, B)) / length(union(A, B))
}

# (a) identical presence patterns
pat <- apply(M, 2, paste0, collapse = "")
info[, pattern := pat[series_code]]
info[, pgid := .GRP, by = pattern]
cand <- info[, .N, by = pgid][N > 1]$pgid
msg("2. groups with identical presence patterns: ", length(cand),
    " covering ", nrow(info[pgid %in% cand]), " series")

# (b) pairwise description similarity within each group: build a graph
# (edge = descriptions similar enough) and take connected components. A
# component with more than one member is a duplicate group; singletons stay
# separate even though they share the pattern.
info[, `:=`(cluster = series_code, verdict = "single", evidence = "")]

for (g in cand) {
  idx <- which(info$pgid == g)
  s   <- info[idx]
  n   <- nrow(s)
  adj <- matrix(FALSE, n, n)
  sim <- matrix(0, n, n)
  for (i in 1:(n - 1)) for (j in (i + 1):n) {
    v <- jacc(s$ndesc[i], s$ndesc[j]); sim[i, j] <- sim[j, i] <- v
    adj[i, j] <- adj[j, i] <- v >= sim_confirm
  }
  comp <- rep(NA_integer_, n); k <- 0L
  for (i in 1:n) {
    if (!is.na(comp[i])) next
    k <- k + 1L; stack <- i
    while (length(stack)) {
      v <- stack[1]; stack <- stack[-1]
      if (!is.na(comp[v])) next
      comp[v] <- k
      stack <- c(stack, which(adj[v, ] & is.na(comp)))
    }
  }
  for (cc in unique(comp)) {
    mem <- which(comp == cc)
    rows <- idx[mem]
    if (length(mem) > 1) {
      # representative: the alphabetically first code, so the choice is stable
      rep_code <- sort(info$series_code[rows])[1]
      info[rows, `:=`(cluster = rep_code, verdict = "collapse",
        evidence = sprintf("identical pattern; min desc similarity %.2f; indicators %s; units %s",
          min(sim[mem, mem][upper.tri(sim[mem, mem])]),
          paste(unique(info$indicator[rows]), collapse = "/"),
          paste(unique(info$units[rows]), collapse = "/")))]
    } else {
      others <- setdiff(seq_len(n), mem)
      best <- if (length(others)) max(sim[mem, others]) else 0
      info[rows, `:=`(verdict = if (best >= sim_review) "review" else "keep_separate",
        evidence = sprintf("identical pattern with %d other series but best desc similarity only %.2f",
                           length(others), best))]
    }
  }
}

# Every group marked "collapse" must move as one unit in every country-year.
fails <- info[verdict == "collapse", {
  sub <- M[, series_code, drop = FALSE]
  .(disagreeing_country_years =
      sum(apply(sub, 1, function(z) length(unique(z[!is.na(z)])) > 1)))
}, by = cluster][disagreeing_country_years > 0]
if (nrow(fails)) {
  print(fails)
  stop("The duplicate groups above contain series that do NOT always move ",
       "together, so they are not duplicates. Inspect them before going ",
       "further; do not collapse these.", call. = FALSE)
}

variant_map <- info[, .(series_code, indicator, units, series_description,
                        pattern_group = pgid, cluster, verdict, evidence)]
setorder(variant_map, verdict, cluster, series_code)
fwrite(variant_map, file.path(out_dir, "series_variant_map.csv"))
print(variant_map[, .(series = .N), by = verdict][order(-series)])

variant_reps <- variant_map[series_code == cluster | verdict != "collapse"]$series_code
n_before     <- ncol(resp)
resp         <- resp[, colnames(resp) %in% variant_reps, drop = FALSE]
msg("2. duplicates collapsed: ", n_before, " -> ", ncol(resp), " series (",
    uniqueN(variant_map[verdict == "collapse"]$cluster), " groups)")

# ---- 3. ONE GOAL PER SERIES --------------------------------------------------
# A series listed under several goals goes to whichever of ITS OWN goals
# currently has the fewest series, so no goal is starved by an arbitrary
# choice. Taking the lowest goal number instead would strip goal 13 (climate
# action) from 24 series to 2, because every disaster-risk series (VC_DSR_*)
# would land in goal 1.
series_goal <- unique(fread(file.path(out_dir, "series_stability_list.csv"))[
  , .(series_code, goal)])
series_goal <- series_goal[series_code %in% colnames(resp)]

n_by_series <- series_goal[, .N, by = series_code]
solo        <- n_by_series[N == 1]$series_code
shared      <- n_by_series[N > 1]$series_code

counts <- setNames(integer(17), as.character(1:17))
tb <- series_goal[series_code %in% solo][, .N, by = goal]
counts[as.character(tb$goal)] <- tb$N

assign_list <- series_goal[series_code %in% solo,
                           .(series_code, goals_listed = as.character(goal),
                             goal_assigned = goal)]
for (sc in shared) {
  opts <- sort(series_goal[series_code == sc]$goal)
  pick <- opts[which.min(counts[as.character(opts)])]
  counts[as.character(pick)] <- counts[as.character(pick)] + 1L
  assign_list <- rbind(assign_list,
                       data.table(series_code = sc,
                                  goals_listed = paste(opts, collapse = "/"),
                                  goal_assigned = pick))
}
stopifnot(setequal(assign_list$series_code, colnames(resp)),
          !anyDuplicated(assign_list$series_code))
msg("3. ", length(shared), " series span several goals; each assigned to its ",
    "goal with the fewest series")
fwrite(assign_list, file.path(out_dir, "series_goal.csv"))

# ---- WRITE -------------------------------------------------------------------
grid_model_series <- grid_all[, c("iso3", "year", colnames(resp)), with = FALSE]
saveRDS(grid_model_series, file.path(out_dir, "grid_model_series.rds"))
fwrite(grid_model_series, file.path(out_dir, "grid_model_series.csv"))   # same grid, readable without R

filter_log <- data.table(
  step   = 0:3,
  rule   = c("series in the UN exports with a value in 2015-2023",
             paste0("drop series reported in ", item_lo * 100,
                    "% or fewer of country-years"),
             paste0("drop series reported in ", item_hi * 100,
                    "% or more of country-years"),
             "collapse duplicate series (same measurement recorded twice)"),
  series = c(length(p_rep), sum(p_rep > item_lo), sum(keep), ncol(resp)))
fwrite(filter_log, file.path(out_dir, "filter_log.csv"))
print(filter_log)
msg("done.")
