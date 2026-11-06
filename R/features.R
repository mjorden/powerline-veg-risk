# Per-point features for classification.
#
# Features are local: k-nearest-neighbour covariance shape, echo structure,
# intensity and height. They are NOT independent of the weak labels in
# labels.R - the wire rule uses height and empty space beneath a point, which
# `height_m` and the echo features partly encode - so analysis scripts run
# an ablation without those features (see `rule_proxy_features`).
#
# The table carries three attributes that downstream functions rely on:
# `crs` (the point cloud's CRS, so metre parameters are scaled correctly and
# OSM layers land in the right place), `k` (the neighbourhood sizes, so the
# conductor-return test in corridor_rasters() finds the right linearity
# column) and `features` (the allow-list of predictor columns, so a joined
# column or a previous model's predictions never become predictors).

#' Compute per-point classification features
#'
#' @param las A height-normalised `LAS` (see [read_corridor()]).
#' @param k Neighbourhood sizes for the multi-scale eigenvalue features.
#' @param min_height_m Points below this height above ground are not
#'   featurised (they are ground / low cover, handled by the ground class).
#' @return A `data.table` with `pid` (row index into `las@data`), `X`, `Y`,
#'   `Z` (height above ground, native units), `Zref` (the original
#'   elevation, native units, `NA` when the cloud was not height-normalised
#'   with lidR), `class_code` (the delivered ASPRS class), `gpstime` (`NA`
#'   when not read), and feature columns. The table is self-contained: the
#'   risk functions never index back into `las` by row. Attributes `crs`
#'   (the CRS of `las`), `k`, `features` (the predictor column names) and
#'   `las_fingerprint` (point count and extent of `las`, checked by
#'   [corridor_rasters()]) travel with the table through [weak_labels()],
#'   [assign_blocks()] and [predict_points()].
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
    Zref       = if ("Zref" %in% names(sub@data)) sub$Zref else NA_real_,
    class_code = as.integer(sub$Classification),
    gpstime    = if ("gpstime" %in% names(sub@data)) sub$gpstime else NA_real_,
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
  out <- out[]
  attr(out, "crs") <- sf::st_crs(las)
  attr(out, "k") <- as.integer(k)
  attr(out, "features") <- setdiff(names(out), point_id_columns)
  attr(out, "las_fingerprint") <- las_fingerprint(las)
  out
}

# Cheap identity of a point cloud: count and extent. Enough to catch the
# cloud being re-clipped, re-sorted or swapped between featurising and
# rasterising (#55).
las_fingerprint <- function(las) {
  list(n = lidR::npoints(las), xmin = min(las$X), xmax = max(las$X), ymin = min(las$Y), ymax = max(las$Y))
}

# Abort when `feat` was not featurised from this `las`.
check_las_match <- function(las, feat, arg = "pred") {
  fp <- attr(feat, "las_fingerprint")
  if (is.null(fp)) return(invisible(TRUE))
  now <- las_fingerprint(las)
  if (!isTRUE(all.equal(fp, now, tolerance = 1e-9))) {
    rlang::abort(sprintf(paste("`%s` was featurised from a different point cloud than `las`",
                               "(%s points, extent %s) vs (%s points, extent %s).", "Pass the LAS that point_features() saw."),
                         arg, fp$n, paste(round(unlist(fp[-1]), 2), collapse = " "),
                         now$n, paste(round(unlist(now[-1]), 2), collapse = " ")))
  }
  invisible(TRUE)
}

# Intensity is uncalibrated in 3DEP deliveries, so use its within-dataset
# percentile rather than raw counts.
rank_scale <- function(x) (rank(x, ties.method = "average") - 0.5) / length(x)

point_id_columns <- c("pid", "X", "Y", "Z", "Zref", "class_code", "gpstime")

# Predictor columns. Tables from point_features() carry an allow-list; a
# table assembled by hand falls back to everything that is not an id, a
# label, a fold or a model output (`pred`, `p_<class>`).
feature_columns <- function(feat, drop = NULL) {
  vars <- attr(feat, "features")
  if (is.null(vars)) {
    vars <- setdiff(names(feat), c(point_id_columns, "label", "block", "fold", "random_fold", "pred",
                                   grep("^p_", names(feat), value = TRUE)))
  } else {
    missing <- setdiff(vars, names(feat))
    if (length(missing)) {
      rlang::abort(sprintf("`feat` is missing feature column(s) recorded by point_features(): %s",
                           paste(missing, collapse = ", ")))
    }
  }
  setdiff(vars, drop)
}

# Exported entry points accept a data.frame (a features table reloaded with
# readr or arrow) and work on a data.table; the point_features() attributes
# survive the coercion.
as_point_table <- function(x, arg = "feat") {
  if (!is.data.frame(x)) rlang::abort(sprintf("`%s` must be a data.frame or data.table.", arg))
  if (data.table::is.data.table(x)) return(x)
  keep <- attributes(x)[intersect(c("crs", "k", "features"), names(attributes(x)))]
  x <- data.table::as.data.table(x)
  for (nm in names(keep)) attr(x, nm) <- keep[[nm]]
  x
}

# The CRS a features table was built in. `crs` given explicitly must agree
# with the one point_features() recorded; given neither, abort.
feat_crs <- function(feat, crs = NULL) {
  recorded <- attr(feat, "crs")
  if (is.null(crs)) {
    if (is.null(recorded)) {
      rlang::abort("`crs` is missing and `feat` records none (it did not come from point_features()).")
    }
    return(sf::st_crs(recorded))
  }
  crs <- sf::st_crs(crs)
  if (!is.null(recorded) && !is.na(sf::st_crs(recorded)) && crs != sf::st_crs(recorded)) {
    rlang::abort(paste("`crs` differs from the CRS `feat` was featurised in;",
                       "metre parameters and OSM layers would be mis-scaled. Pass the point cloud's CRS."))
  }
  crs
}

# A row order that does not depend on tile or clip order, so seeded
# sampling gives the same result whatever order the points arrived in.
stable_order <- function(dt) {
  by <- intersect(c("X", "Y", "Z", "pid"), names(dt))
  if (length(by) == 0) return(dt)
  dt[do.call(order, unname(as.list(dt[, by, with = FALSE])))]
}

#' Features that directly encode the wire-labelling rule
#'
#' Height and echo-structure features: dropping them in cross-validation
#' shows how much accuracy comes from re-learning the rule.
#' @format A character vector of feature column names.
#' @export
rule_proxy_features <- c("height_m", "n_returns", "return_pos", "single_ret")
