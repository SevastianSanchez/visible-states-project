# ==============================================================================
# fitting.R -- the goal model, written once.
#
# Sourced, never run. Used by three scripts that must fit the SAME model:
#   03_measures/vsi_goal/build_irt_vsi_goal.R                        the published fit
#   03_measures/vsi_goal/validate_measure/validate_vsi_goal_bootstrap.R
#   03_measures/vsi_goal/validate_measure/validate_vsi_goal_heldout.R
#
# Why one copy: the bootstrap and the held-out check test the published scores
# only if they refit the published model. Before 23 Nov 2026 each script carried
# its own copy and the two checks typed the prior (2), tolerance and cycle cap
# directly, so changing the published fit would have left both checks quietly
# testing the old model. Now a change here reaches all three.
#
# The settings are from METHODS_LOG.md. Do not change one without reading it.
#   squarem          binary model; ~20x fewer cycles than mirt's default
#   prior norm(0,2)  on the slopes (a1). Collinear series inside one goal give
#                    the factor an unbounded slope; the prior bounds it without
#                    dropping series. Not lognormal: some slopes are negative.
#   TOL 1e-3         mirt's 1e-4 is unreachable on a flat ridge of near-zero
#                    slopes; shown to move no score by more than 0.0065
#   5,000 cycles     cap; a fit that reaches it is not publishable
# ==============================================================================

goal_prior_sd   <- 2
goal_tol        <- 1e-3
goal_max_cycles <- 5000L

# One unidimensional 2PL on one goal's series. M: country-years x series, 0/1.
# Returns the mirt fit. Callers handle scoring, sign and failure themselves,
# because those differ between the published fit and the two checks.
fit_goal_2pl <- function(M) {
  v <- mirt::mirt(M, 1, itemtype = "2PL", pars = "values")
  i <- grepl("^a1$", v$name) & v$est
  v$prior.type[i] <- "norm"; v$prior_1[i] <- 0; v$prior_2[i] <- goal_prior_sd
  suppressWarnings(mirt::mirt(M, 1, itemtype = "2PL", pars = v, verbose = FALSE,
                              accelerate = "squarem", TOL = goal_tol,
                              technical = list(NCYCLES = goal_max_cycles, warn = FALSE)))
}
