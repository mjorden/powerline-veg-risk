# Per-point features for classification.
#
# Features are local: k-nearest-neighbour covariance shape, echo structure,
# intensity and height. They are NOT independent of the weak labels in
# labels.R - the wire rule uses height and empty space beneath a point, which
# `height_m` and the echo features partly encode - so analysis scripts run
# an ablation without those features (see `rule_proxy_features`).

#' Compute per-point classification features
#'
#' @param las A height-normalised `LAS` (see [read_corridor()]).
#' @param k Neighbourhood sizes for the multi-scale eigenvalue features.
#' @param min_height_m Points below this height above ground are not
#'   featurised (they are ground / low cover, handled by the ground class).
#' @return A `data.table` with `pid` (row index into `las@data`), `X`, `Y`,
#'   `Z`, and feature columns.
#' @export
point_features <- function(las, k = c(10L, 30L), min_height_m = 2) {
  m <- las_m_per_unit(las)
  above <- which(las$Z >= min_height_m / m & las$Classification != 2L)
  if (length(above) < max(k) + 1) rlang::abort("Too few above-ground points to featurise.")

  sub <- lidR::filter_poi(las, Z >= min_height_m / m & Classification != 2L)
  out <- data.table::data.table(
    pid        = above,
    X          = sub$X,
    Y          = sub$Y,
    Z          = sub$Z,
    height_m   = sub$Z * m,
    intensity  = rank_scale(sub$Intensity),
    n_returns  = sub$NumberOfReturns,
    return_pos = (sub$ReturnNumber - 1) / pmax(sub$NumberOfReturns - 1, 1),
    single_ret = as.integer(sub$NumberOfReturns == 1L)
  )

  # Eigen features are computed in 3D on the *above-ground* cloud so that
  # ground points do not dominate neighbourhoods of low conductors.
  for (kk in k) {
    e <- lidR::point_eigenvalues(sub, k = kk, metrics = TRUE)
    sfx <- paste0("_k", kk)
    out[, (paste0("linearity", sfx))  := e$linearity]
    out[, (paste0("planarity", sfx))  := e$planarity]
    out[, (paste0("sphericity", sfx)) := e$sphericity]
    out[, (paste0("curvature", sfx))  := e$curvature]
    # Size of the neighbourhood: isolated wire points have sparse,
    # elongated neighbourhoods; canopy is dense.
    out[, (paste0("eig_sum", sfx)) := log1p((e$eigen_largest + e$eigen_medium + e$eigen_smallest) * m^2)]
  }
  out[]
}

# Intensity is uncalibrated in 3DEP deliveries, so use its within-dataset
# percentile rather than raw counts.
rank_scale <- function(x) (rank(x, ties.method = "average") - 0.5) / length(x)

feature_columns <- function(feat, drop = NULL) {
  setdiff(names(feat), c("pid", "X", "Y", "Z", "label", "block", "fold", "random_fold", drop))
}

#' Features that directly encode the wire-labelling rule
#'
#' Height and echo-structure features: dropping them in cross-validation
#' shows how much accuracy comes from re-learning the rule.
#' @format A character vector of feature column names.
#' @export
rule_proxy_features <- c("height_m", "n_returns", "return_pos", "single_ret")
