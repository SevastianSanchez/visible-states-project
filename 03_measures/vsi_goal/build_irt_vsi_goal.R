# ==============================================================================
# build_irt_vsi_goal.R
#
# Fit 2 of 3: the goal-level scores (vsi_goal). One reporting score per country-year PER GOAL.
# Independent of build_irt_vsi.R -- neither can delay or break the other.
#
# WHAT THIS IS
#   The overall index (vsi) answers "how much did this country report". This answers
#   "how much did it report ON GOAL g". One separate unidimensional 2PL per
#   goal, fitted on that goal's own series only.
#
#   The column is `vsi_goal`: reporting on that goal with the country's
#   overall level INCLUDED. Its companion `vsi_goal_relative` -- the same quantity
#   with the overall level stripped out -- comes from a bifactor model and is
#   built by its own script, because that fit takes hours and must not be able
#   to hold this one up.
#
#   Why separate fits and not one 17-factor model? Both are wanted and they
#   answer different questions. A separate fit per goal is also what makes the
#   held-out test below possible: a goal's score owes nothing to the other 16.
#
# WHY THESE SETTINGS
#   Taken from METHODS_LOG.md, not chosen here, and set in one place:
#   03_measures/functions/fitting.R, which the bootstrap and held-out checks
#   also use, so they always refit this exact model. Do not change one without
#   reading METHODS_LOG.md; each of these cost hours to establish.
#
#   accelerate = "squarem"   Binary model. mirt's default Ramsay accelerator
#                            reaches the same fixed point ~20x slower; it ran
#                            the bifactor past 19 h without returning.
#   prior norm(0, 2) on a1   The pre-flight screen finds 9 groups of perfectly
#                            collinear series. Inside a single factor those
#                            make the factor a copy of the block, and the
#                            block's discrimination has no finite value. The
#                            prior bounds it without deleting the series.
#                            NOT lognormal: 172 of 1,045 loadings are negative
#                            and lognormal gives those zero density, which
#                            would force sign flips.
#   TOL = 1e-3               mirt's 1e-4 is unreachable here: a handful of
#                            near-zero loadings and extreme intercepts sit on
#                            a flat ridge and drift below 1e-3 forever. Shown
#                            to change no score by more than 0.0065 against
#                            SEs of 0.3-0.5.
#
# WHAT IS AND IS NOT RELEASED
#   Every goal fitted here ships, each printed with its reliability and SE.
#   Nothing is dropped for imprecision; 0.70 (Nunnally & Bernstein 1994) is a reference point,
#   not a cut. Goals 6 and 15 are fitted and written but flagged `hold`, on
#   CONTENT grounds and for different reasons -- see CLAUDE.md. An error bar
#   cannot warn a reader about either, so the flag travels with the data.
#
#   Goal 7 gets no score. It has 3 series, below the >=10 needed to identify a
#   factor. That is a structural fact about the goal, not a judgement on it.
#
# EVIDENCE THESE SCORES CARRY (9 Nov 2026, see METHODS_LOG.md)
#   Reliability  0.772 - 0.953, median 0.844; every goal above 0.70.
#   Bootstrap    B = 500, 0 failed replicates. Bootstrap SD is 7-42% of the
#                posterior SE, median 13% -- the published SEs are
#                conservative, so report the SE, not the bootstrap SD.
#   Held-out     Fit on 70% of a goal's series, predict the held-out 30%.
#                Median AUC 0.725 against a per-series permutation null that
#                sits on 0.500. 13 of 16 goals at 0.649 or better. The three
#                weakest -- 17 (0.618), 15 (0.526), 6 (0.479) -- are exactly
#                the three already flagged on content grounds.
#
# RUNTIME  under a minute for all 16 goals. No checkpointing needed.
#
# INPUT   01_data/processed/grid_all_series.rds, grid_model_series.rds and
#         series_goal.csv (02_processing/03 and 04), via 03_measures/functions/model_data.R
# OUTPUT  01_data/vsi_scores/vsi_goal/irt_vsi_goal_{scores.csv,scores.rds,
#         item_params.csv,health.csv,run_log.csv,fits.rds}
#         This script writes no file that build_irt_vsi.R writes.
# ==============================================================================

source(here::here("03_measures/functions/model_data.R"))
list2env(model_inputs(
  readRDS(here::here("01_data/processed/grid_all_series.rds")),
  readRDS(here::here("01_data/processed/grid_model_series.rds")),
  data.table::fread(here::here("01_data/processed/series_goal.csv")),
  min_series_per_goal), environment())
source(here::here("03_measures/functions/fitting.R"))
set.seed(20261105)   # the seed the published fits used, so they reproduce exactly

suppressMessages({library(mirt); library(data.table); library(here)})

# Provenance, for disclosure only. `Nature` in the UN exports marks whether a
# value is country-produced (C/CA) or produced by the custodian agency (E/M/G).
# Built by 02_processing/build_series_provenance.R; absent is not fatal.
prov_path <- here::here("01_data/processed/series_provenance_nature.csv")
prov <- if (file.exists(prov_path)) data.table::fread(prov_path) else NULL

MIN_SERIES   <- min_series_per_goal   # rules.R: below this a factor is not identified
REL_REF      <- 0.70     # reported as a reference point, never applied as a cut
HOLD_CONTENT <- goals_held   # rules.R: withheld on content grounds

# ---- ONE GOAL ----------------------------------------------------------------
fit_goal <- function(g) {
  cs <- colnames(resp)[item_goal == g]
  M  <- resp[, cs, drop = FALSE]

  # Safety check, not a filter. The 2-98% filter already ran in
  # 02_processing/04_select_model_series_sdg.R on
  # the same 1,773 country-years, so no series here should fail it. If one
  # does, that script has changed and the goal fits must not run on its output.
  # Cutoffs come from rules.R (item_lo, item_hi), not retyped here.
  p   <- colMeans(M)
  bad <- !(p > item_lo & p < item_hi)
  if (any(bad))
    stop("goal ", g, ": ", sum(bad), " series reported in ", item_lo * 100,
         "% or fewer, or ", item_hi * 100, "% or more, of country-years ",
         "reached the goal fit (", paste(cs[bad], collapse = ", "), "). The ",
         "2-98% filter in 04_select_model_series_sdg.R should have removed ",
            "them; check it ",
         "before fitting.", call. = FALSE)

  if (ncol(M) < MIN_SERIES) {
    msg(sprintf("  goal %-2d  series %3d  -- SKIPPED, under %d, factor not identified",
                g, ncol(M), MIN_SERIES))
    return(NULL)
  }

  t0 <- Sys.time()
  f  <- fit_goal_2pl(M)   # functions/fitting.R
  mins <- as.numeric(difftime(Sys.time(), t0, units = "mins"))

  th <- fscores(f, method = "EAP", full.scores.SE = TRUE)

  # Orient the factor so that MORE reporting is a HIGHER score. A 2PL is
  # identified only up to sign, and the sign mirt lands on is arbitrary, so
  # without this a goal could silently flip between runs.
  s <- th[, 1] * sign(cor(th[, 1], rowSums(M)))

  rel  <- var(s) / (var(s) + mean(th[, 2]^2))
  conv <- extract.mirt(f, "converged")
  cyc  <- extract.mirt(f, "iterations")
  amax <- max(abs(coef(f, simplify = TRUE)$items[, "a1"]))

  # Publishable means: the optimiser converged, it did not simply hit the cap,
  # and every score has a finite standard error. max|a| is REPORTED, not gated:
  # a slope of 10-17 here is a near-duplicate series bounded by the prior, which
  # is the prior working, not divergence. The bifactor's max|a| < 10 rule in
  # METHODS_LOG.md was written for a model where a factor became a copy of a
  # collinear block and slopes ran past 80. See the Nov 9 diagnostic rows.
  ok <- conv && cyc < goal_max_cycles && !any(is.na(th[, 2])) && all(th[, 2] > 0)

  msg(sprintf("  goal %-2d  series %3d  cycles %5d  conv=%-5s  max|a| %5.2f  rel %.3f  medSE %.3f  %.1f min%s",
      g, ncol(M), cyc, conv, amax, rel, median(th[, 2]), mins,
      if (!ok) "   <-- CHECK" else ""))

  co <- as.data.table(coef(f, simplify = TRUE)$items, keep.rownames = "series_code")
  # `g` is BOTH this function's argument and a column of a 2PL coefficient
  # matrix (the guessing parameter, fixed at 0). Inside `[`, data.table resolves
  # the column, so `goal := g` silently wrote 0 for every series. Use the
  # argument explicitly.
  goal_number <- g
  co[, goal := goal_number][, p_reported := round(colMeans(M)[series_code], 4)]
  co[, weight_pct := round(100 * abs(a1) / sum(abs(a1)), 2)]

  # concentration: share of the score's weight in its five heaviest series
  top5 <- sum(sort(co$weight_pct, decreasing = TRUE)[1:min(5, nrow(co))])
  # provenance: share of weight from series that are mostly NOT country-produced
  agency_w <- if (!is.null(prov)) {
    pc <- prov$pct_C[match(co$series_code, prov$SeriesCode)]
    sum(co$weight_pct[!is.na(pc) & pc < 50])
  } else NA_real_

  list(
    goal   = g,
    scores = data.table(iso3 = keys$iso3, year = keys$year, goal = g,
                        vsi_goal    = round(s, 4),
                        vsi_goal_se = round(th[, 2], 4)),
    params = co,
    health = data.table(goal = g, series = ncol(M), cycles = cyc,
                        converged = conv, clean = ok,
                        max_abs_a   = round(amax, 3),
                        # disclosure, not gates: how concentrated the score is,
                        # and how much of its weight rests on series the
                        # custodian agency produces rather than the country
                        weight_top5_pct  = round(top5, 1),
                        weight_agency_pct = round(agency_w, 1),
                        reliability = round(rel, 3),
                        above_ref   = rel >= REL_REF,
                        se_median   = round(median(th[, 2]), 3),
                        se_max      = round(max(th[, 2]), 3),
                        release     = if (g %in% HOLD_CONTENT) "hold_content" else "release",
                        minutes     = round(mins, 2)),
    fit    = f)
}

# ---- ALL GOALS ---------------------------------------------------------------
msg("vsi_goal: one 1-factor 2PL per goal | squarem | prior norm(0, ", goal_prior_sd,
    ") | TOL ", goal_tol)

t_all <- Sys.time()
res   <- Filter(Negate(is.null), lapply(sort(unique(item_goal)), fit_goal))
mins  <- as.numeric(difftime(Sys.time(), t_all, units = "mins"))

scores <- rbindlist(lapply(res, `[[`, "scores"))
params <- rbindlist(lapply(res, `[[`, "params"))
health <- rbindlist(lapply(res, `[[`, "health"))
setorder(scores, iso3, year, goal)
setorder(health, goal)

# ---- GUARDS ------------------------------------------------------------------
# An unconverged or degenerate fit is not publishable. Halt loudly rather than
# writing quietly; a bad score that reaches data/ is worse than no score.
stopifnot(
  nrow(health) >= 15L,
  nrow(scores) == nrow(health) * nrow(resp),
  !any(is.na(scores$vsi_goal)),
  !any(is.na(scores$vsi_goal_se))
)
if (!all(health$clean)) {
  print(health[clean == FALSE])
  stop("one or more goals is not publishable (did not converge, hit the cycle ",
       "cap, or has a non-finite standard error) -- nothing written. ",
       "Read METHODS_LOG.md before changing a setting.")
}

# ---- WRITE -------------------------------------------------------------------
msg("writing")
out <- here("01_data/vsi_scores/vsi_goal")

saveRDS(setNames(lapply(res, `[[`, "fit"), sapply(res, `[[`, "goal")),
        file.path(out, "irt_vsi_goal_fits.rds"))
fwrite(scores,  file.path(out, "irt_vsi_goal_scores.csv"))
saveRDS(scores, file.path(out, "irt_vsi_goal_scores.rds"))
fwrite(params,  file.path(out, "irt_vsi_goal_item_params.csv"))
fwrite(health,  file.path(out, "irt_vsi_goal_health.csv"))

fwrite(data.table(
  run_date        = as.character(Sys.Date()),
  fit             = "unidimensional 2PL, one per goal",
  n_country_years = nrow(resp),
  n_series_total  = ncol(resp),
  goals_fitted    = nrow(health),
  goals_skipped   = paste(setdiff(sort(unique(item_goal)), health$goal), collapse = "/"),
  goals_held      = paste(HOLD_CONTENT, collapse = "/"),
  accelerate      = "squarem",
  prior           = paste0("norm(0,", goal_prior_sd, ") on a1"),
  tol             = goal_tol,
  max_cycles      = goal_max_cycles,
  all_converged   = all(health$converged),
  median_reliability = median(health$reliability),
  min_reliability    = min(health$reliability),
  median_se       = round(median(scores$vsi_goal_se), 4),
  minutes         = round(mins, 2),
  mirt_version    = as.character(packageVersion("mirt")),
  r_version       = paste(R.version$major, R.version$minor, sep = ".")),
  file.path(out, "irt_vsi_goal_run_log.csv"))

cat("\n"); print(health)
cat("\ngoals fitted:", nrow(health),
    "| all converged:", all(health$converged),
    "| median reliability:", median(health$reliability),
    "| all above", REL_REF, ":", all(health$above_ref), "\n")
msg("done. rows: ", nrow(scores))
