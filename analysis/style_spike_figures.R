# Before/after figures for the mid-mod style spike (analysis/style-spike.md).
#
#   Rscript analysis/style_spike_figures.R [out_dir]
#
# Renders plot_risk_map() and plot_cv() in the "classic" (default) and
# "midmod" styles from the synthetic fixtures of tests/testthat/test-risk.R,
# and from the case-study outputs when they are present:
#   output/<id>/cv_metrics.csv          (written by analysis/pipeline.R)
#   output/spike/<id>_riskmap_inputs.rds (rasters/risk/supports captured from
#                                        a VEGRISK_REUSE=1 pipeline run)

devtools::load_all(quiet = TRUE)
out <- commandArgs(TRUE)[1]
if (is.na(out)) out <- "analysis/figures/style-spike"
dir.create(out, showWarnings = FALSE, recursive = TRUE)

# --- Synthetic fixtures (tests/testthat/test-risk.R) -------------------------
ex <- parse("tests/testthat/test-risk.R")
is_test <- vapply(ex, function(e) is.call(e) && identical(e[[1]], as.name("test_that")), logical(1))
fx <- new.env(parent = asNamespace("vegrisk"))
for (e in ex[!is_test]) eval(e, fx)

synthetic_risk <- function(trees) {
  r <- fx$make_rasters(trees)
  ln <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(rbind(c(fx$x0, fx$y0), c(fx$x0 + 200, fx$y0))),
                                        crs = fx$utm))
  s <- segment_lines(ln, fx$utm, seg_m = 20)
  prof <- conductor_profile(fx$no_wires, s, r$dtm, min_ground_clear_m = 10, attach_m = 10)
  list(rasters = r, risk = assess_risk(r, prof, s, phase_offset_m = 3, tree_ws_m = 3))
}
# Grow-in under the line at 25 m and 95 m, strike trees beside it, a stand of
# short trees that never reach the line, and an "unobserved" patch where
# conductor returns would have been removed.
trees <- data.frame(x = fx$x0 + c(25.5, 95.5, 50.5, 120.5, 150.5, 170.5, 30, 60, 140, 175),
                    y = fx$y0 + c(0.5, 1.5, 13.5, 12.5, -13.5, 14.5, 35, -30, 33, -38),
                    h = c(9, 9.5, 15, 16, 14, 12, 22, 18, 26, 8))
syn <- synthetic_risk(trees)
un <- terra::setValues(syn$rasters$dtm, FALSE)
xy <- terra::crds(un, na.rm = FALSE)
un[abs(xy[, 2] - fx$y0) < 4 & xy[, 1] > fx$x0 + 130 & xy[, 1] < fx$x0 + 160] <- TRUE
syn$rasters$unobserved <- un & is.na(syn$rasters$chm)
# Every segment at zero encroachment: the #5 case (Nashville).
syn0 <- synthetic_risk(trees[c(3, 4, 5, 7, 8, 9), ])

syn_cv <- data.frame(
  scheme = rep(c("random", "spatial_block", "spatial_ablation"), each = 4),
  class = rep(c("vegetation", "wire", "structure", "building"), 3),
  n = rep(c(412000, 180, 2600, 5100), 3),
  prevalence = rep(c(0.978, 0.0004, 0.006, 0.012), 3),
  avg_precision = c(0.999, 0.41, 0.81, 0.93, 0.998, 0.004, 0.52, 0.71, 0.995, 0.003, 0.18, 0.44),
  recall = c(0.999, 0.12, 0.66, 0.85, 0.998, 0, 0.31, 0.58, 0.996, 0, 0.05, 0.22)
)

for (style in c("classic", "midmod")) {
  withr::with_options(list(vegrisk.style = style), {
    plot_risk_map(syn$rasters, syn$risk, title = "Synthetic corridor (test-risk.R fixtures)",
                  source = "synthetic", file = file.path(out, sprintf("synthetic_risk_map_%s.png", style)))
    plot_risk_map(syn0$rasters, syn0$risk, title = "Synthetic corridor, no grow-in",
                  source = "synthetic", file = file.path(out, sprintf("synthetic_zero_risk_map_%s.png", style)))
    plot_cv(syn_cv, file.path(out, sprintf("synthetic_cv_%s.png", style)))
    for (id in c("sunshine", "nashville")) {
      cv <- file.path("output", id, "cv_metrics.csv")
      if (file.exists(cv)) plot_cv(utils::read.csv(cv), file.path(out, sprintf("%s_cv_%s.png", id, style)))
      rds <- file.path("output/spike", paste0(id, "_riskmap_inputs.rds"))
      if (file.exists(rds)) {
        x <- readRDS(rds)
        x$rasters <- lapply(x$rasters, function(r) if (inherits(r, "PackedSpatRaster")) terra::unwrap(r) else r)
        plot_risk_map(x$rasters, x$risk, x$structures, title = x$title, source = x$source,
                      file = file.path(out, sprintf("%s_risk_map_%s.png", id, style)))
      }
    }
  })
}
