# Synthetic corridor: an E-W line along y = 0, conductor 10 m above ground,
# and conical trees placed at known distances.
utm <- sf::st_crs(26913)
x0 <- 500000
y0 <- 4400000

make_rasters <- function(trees, slope = 0) {
  r <- terra::rast(xmin = x0, xmax = x0 + 200, ymin = y0 - 50, ymax = y0 + 50,
                   resolution = 1, crs = "EPSG:26913")
  xy <- terra::crds(r, na.rm = FALSE)
  # Ground rises `slope` metres per metre north of the line.
  dtm <- terra::setValues(r, slope * pmax(xy[, 2] - y0, 0))
  h <- numeric(nrow(xy))
  for (i in seq_len(nrow(trees))) {
    d <- sqrt((xy[, 1] - trees$x[i])^2 + (xy[, 2] - trees$y[i])^2)
    h <- pmax(h, trees$h[i] - 2 * d) # cone, 2 m drop per metre
  }
  chm <- terra::setValues(r, ifelse(h > 0, h, NA))
  list(dtm = dtm, chm = chm)
}

segs <- function() {
  ln <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(x0, y0), c(x0 + 200, y0))), crs = utm))
  segment_lines(ln, utm, seg_m = 100)
}

no_wires <- data.table::data.table(X = numeric(), Y = numeric(), height_m = numeric(),
                                   pred = factor(character(), levels = label_levels))

# Flat ground along the line, so both bounds put the conductor at 10 m.
risk_for <- function(r, ...) {
  s <- segs()
  prof <- conductor_profile(no_wires, s, r$dtm, min_ground_clear_m = 10, attach_m = 10)
  assess_risk(r, prof, s, ...)
}

test_that("fall-in uses 3D reach from tree base to conductor", {
  # phase offset 3 m: horizontal reach 13 - 3 = 10, vertical 10 -> 14.14 m
  trees <- data.frame(x = x0 + c(50.5, 150.5), y = y0 + 13.5, h = c(15, 12))
  rk <- risk_for(make_rasters(trees), phase_offset_m = 3, tree_ws_m = 3)
  tt <- rk$trees[order(rk$trees$height_m), ]
  expect_equal(nrow(tt), 2)
  expect_equal(tt$reach_lo_m, rep(sqrt(10^2 + 10^2), 2), tolerance = 0.1)
  expect_identical(tt$strike, c(FALSE, TRUE))
  s <- sf::st_drop_geometry(rk$segments)
  expect_equal(s$n_strike_lo[s$seg_id == 1], 1)
  expect_equal(s$n_strike_lo[s$seg_id == 2], 0)
})

test_that("an upslope tree is more dangerous than the same tree on flat ground", {
  trees <- data.frame(x = x0 + 100.5, y = y0 + 13.5, h = 12)
  flat <- risk_for(make_rasters(trees, slope = 0), phase_offset_m = 3, tree_ws_m = 3)
  up <- risk_for(make_rasters(trees, slope = 0.6), phase_offset_m = 3, tree_ws_m = 3)
  expect_false(flat$trees$strike)
  # base is 13.5 * 0.6 = 8.1 m above line ground -> vertical gap 1.9 m;
  # horizontal 13.5 - 3 = 10.5 m
  expect_equal(up$trees$reach_lo_m, sqrt(10.5^2 + 1.9^2), tolerance = 0.01)
  expect_true(up$trees$strike)
})

test_that("fall-in reach is the minimum 3D distance along the span, not at the nearest station (#19)", {
  trees <- data.frame(x = x0 + 20.5, y = y0 + 13.5, h = 29)
  r <- make_rasters(trees)
  s <- segs()
  prof <- line_vertex_table(s, utm)
  prof$seg_id <- 1L
  prof$ground <- 0
  prof$src <- "measured"
  # The conductor is 30 m up at the tree's station and descends 0.5 m per
  # metre eastward: a few metres along the line it is closer in 3D.
  prof$z_lo <- prof$z_hi <- pmax(30 - 0.5 * (prof$s_m - 20), 5)
  rk <- assess_risk(r, prof, s, phase_offset_m = 3, tree_ws_m = 3)
  tt <- rk$trees
  expect_equal(nrow(tt), 1)
  # Nearest station: sqrt(10.5^2 + 30^2) = 31.8 > 29. About 13 m along:
  # horizontal sqrt(13.5^2 + 13^2) - 3 = 15.7, vertical 23.5 -> 28.3 < 29.
  expect_gt(sqrt(10.5^2 + 30^2), 29)
  expect_equal(tt$reach_lo_m, 28.3, tolerance = 0.01)
  expect_lt(tt$dz_lo_m, 30)
  expect_true(tt$strike)
  # The horizontal distance reported is still the one to the line itself.
  expect_equal(tt$dh_m, 13.5, tolerance = 0.01)
})

test_that("canopy under the line triggers grow-in priority", {
  trees <- data.frame(x = x0 + 25.5, y = y0 + 0.5, h = 9) # 1 m below a 10 m conductor
  rk <- risk_for(make_rasters(trees), tree_ws_m = 3, clearance_target_m = 4.6)
  s <- sf::st_drop_geometry(rk$segments)
  expect_equal(as.character(s$priority[s$seg_id == 1]), "grow-in")
  expect_equal(s$min_clearance_lo_m[s$seg_id == 1], 1, tolerance = 0.01)
  expect_gte(s$encroach_lo_m2[s$seg_id == 1], 5)
  expect_equal(as.character(s$priority[s$seg_id == 2]), "none")
})

test_that("a one-cell spike under the line (unmapped pole) is not a tree", {
  r <- make_rasters(data.frame(x = x0 + 150.5, y = y0 + 20.5, h = 4))
  pole <- terra::cellFromXY(r$chm, cbind(x0 + 50.5, y0 + 0.5))
  r$chm[pole] <- 18
  rk <- risk_for(r, tree_ws_m = 3)
  s <- sf::st_drop_geometry(rk$segments)
  expect_equal(s$n_strike_lo[s$seg_id == 1], 0)
  expect_equal(as.character(s$priority[s$seg_id == 1]), "none")
})

test_that("trees directly under the line are grow-in, not strike trees", {
  trees <- data.frame(x = x0 + 25.5, y = y0 + 2.5, h = 16)
  rk <- risk_for(make_rasters(trees), tree_ws_m = 3)
  expect_false(any(rk$trees$strike))
  s <- sf::st_drop_geometry(rk$segments)
  expect_equal(as.character(s$priority[s$seg_id == 1]), "grow-in")
})

test_that("zero treetops returns a full, empty trees schema", {
  r <- make_rasters(data.frame(x = x0 + 1, y = y0 + 40, h = 0.5))
  rk <- risk_for(r)
  expect_equal(nrow(rk$trees), 0)
  expect_true(all(c("strike", "strike_lo", "strike_hi", "reach_lo_m") %in% names(rk$trees)))
})

test_that("taut-span upper bound bridges a gully instead of following it", {
  s <- seq(0, 300, 1)
  ground <- ifelse(abs(s - 150) < 50, -30 * (1 - abs(s - 150) / 50), 0) # 30 m V-gully
  up <- taut_upper(s, ground + 18, max_span = 250, step = 5)
  expect_equal(up[s == 150], 18, tolerance = 0.5)   # chord between the rims
  expect_equal(up[s == 0], 18, tolerance = 0.5)
  short <- taut_upper(s, ground + 18, max_span = 20, step = 5)
  expect_lt(short[s == 150], 0)                    # short spans must follow terrain
})

test_that("measured conductor overrides the bounds and gaps are not bridged", {
  b <- data.frame(s_m = c(10, 20, 30, 100), z = c(20, 19, 20, 22))
  zz <- interp_with_gaps(b, s = c(15, 25, 60, 120), bin_m = 5, max_gap = 30)
  expect_equal(zz[1:2], c(19.5, 19.5))
  expect_true(is.na(zz[3]))   # 70 m gap
  expect_true(is.na(zz[4]))   # beyond last bin
})

test_that("structure mask removes an H-frame that passes the crown-support filter", {
  r <- make_rasters(data.frame(x = x0 + 150.5, y = y0 + 30.5, h = 4))
  frame <- terra::cellFromXY(r$chm, as.matrix(expand.grid(x0 + 49:51 + 0.5, y0 + (-5:5) + 0.5)))
  r$chm[frame] <- 18
  hfr <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(x0 + 50, y0)), crs = utm))
  without <- sf::st_drop_geometry(risk_for(r, tree_ws_m = 3)$segments)
  with <- sf::st_drop_geometry(risk_for(r, tree_ws_m = 3, structures = hfr)$segments)
  expect_equal(as.character(without$priority[without$seg_id == 1]), "grow-in")
  expect_equal(as.character(with$priority[with$seg_id == 1]), "none")
})

test_that("support chords bound the conductor and are unknown past the last support", {
  sup <- data.frame(s_m = c(100, 400), z = c(120, 60))
  up <- support_chord(c(50, 100, 250, 400, 450), sup)
  expect_equal(up, c(Inf, 120, 90, 60, Inf))
})

test_that("implausible measured bins are dropped", {
  b <- data.frame(s_m = c(10, 15, 20, 25, 60, 200), z = c(20, 20.5, 32, 21, 25, 90))
  kept <- plausible_bins(b, max_slope = 0.2)
  expect_equal(kept$s_m, c(10, 15, 25, 60))   # the 32 m spike and the lone far bin go
})

test_that("conductor returns beside a support are ignored", {
  r <- make_rasters(data.frame(x = x0 + 150.5, y = y0 + 40.5, h = 4))
  s <- segs()
  # guy-wire-like returns 3-8 m up within 5 m of a support at x0 + 50
  guy <- data.table::data.table(X = x0 + seq(46, 54, 0.25), Y = y0, height_m = seq(3, 8, length.out = 33),
                                pred = factor("wire", levels = label_levels),
                                label = factor("wire", levels = label_levels))
  sup <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(x0 + 50, y0)), crs = utm))
  prof <- conductor_profile(guy, s, r$dtm, supports = sup)
  expect_true(all(prof$src == "bounded"))
  prof_nomask <- conductor_profile(guy, s, r$dtm, supports = sup, structure_mask_m = 0)
  expect_false(any(prof_nomask$src == "measured")) # below the 4.9 m floor or too steep
})

test_that("conductor returns crossing canopy are kept out of the canopy model", {
  set.seed(4)
  g <- expand.grid(X = x0 + seq(0, 60, 0.5), Y = y0 + seq(-20, 20, 0.5))
  ground <- data.frame(g, Z = 0, Classification = 2L)
  tree <- data.frame(X = x0 + 30 + runif(400, -2, 2), Y = y0 + runif(400, -2, 2),
                     Z = runif(400, 2, 8), Classification = 1L)
  wire <- data.frame(X = x0 + seq(0, 60, 0.25), Y = y0, Z = 12, Classification = 1L)
  # A second crown, beside the line, that reaches wire height: not linear.
  tall <- data.frame(X = x0 + 15 + runif(400, -2, 2), Y = y0 + 3 + runif(400, -2, 2),
                     Z = runif(400, 2, 13), Classification = 1L)
  pts <- rbind(ground, tree, wire, tall)
  pts$ReturnNumber <- 1L
  pts$NumberOfReturns <- 1L
  pts$Intensity <- 100L
  las <- lidR::LAS(data.table::as.data.table(pts), crs = sf::st_crs(utm))
  las <- lidR::normalize_height(las, lidR::tin())
  ag <- which(las$Classification != 2L)
  pred <- data.table::data.table(pid = ag, X = las$X[ag], Y = las$Y[ag], height_m = las$Z[ag],
                                 pred = factor("vegetation", levels = label_levels),
                                 label = factor("vegetation", levels = label_levels))
  is_wire_pt <- abs(pred$Y - y0) < 1e-6 & abs(pred$height_m - 12) < 1e-6
  pred[, linearity_k10 := ifelse(is_wire_pt, 0.95, 0.2)]
  ln <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(rbind(c(x0, y0), c(x0 + 60, y0))), crs = utm))
  s <- segment_lines(ln, utm, seg_m = 30)
  prof <- line_vertex_table(s, utm)
  prof$seg_id <- 1L
  prof$ground <- 0
  prof$z_lo <- prof$z_hi <- 12
  prof$src <- "measured"

  naive <- corridor_rasters(las, pred)
  clean <- corridor_rasters(las, pred, profile = prof, envelope_m = 5)
  at_tree <- cbind(x0 + 30.25, y0 + 0.25)
  expect_gt(terra::extract(naive$chm, at_tree)[, 1], 11)   # wire sets the CHM
  expect_lt(terra::extract(clean$chm, at_tree)[, 1], 8.5)  # tree height restored
  expect_equal(clean$n_conductor_excluded, nrow(wire))
  # the tall, non-linear crown keeps its top
  expect_gt(max(terra::extract(clean$chm, cbind(x0 + 15 + c(-1, 0, 1), y0 + 3))[, 1], na.rm = TRUE), 11)
  # cells holding only conductor returns are unobserved, not bare ground
  far <- cbind(x0 + 50.1, y0 + c(-0.1, 0.1))  # wire lies on a cell boundary
  expect_true(any(terra::extract(clean$unobserved, far)[, 1] == 1))

  # A bundled conductor is ribbon-like (low linearity): the air gap above
  # the 8 m tree still identifies it, and the tall crown is still kept.
  pred[, linearity_k10 := 0.2]
  ribbon <- corridor_rasters(las, pred, profile = prof, envelope_m = 5)
  expect_lt(terra::extract(ribbon$chm, at_tree)[, 1], 8.5)
  expect_gt(max(terra::extract(ribbon$chm, cbind(x0 + 15 + c(-1, 0, 1), y0 + 3))[, 1], na.rm = TRUE), 11)
})

test_that("structure-masked cells stay unobserved through the crown-support filter (#27)", {
  # Closed 9 m canopy everywhere, with a structure in the wire zone of
  # segment 1. Before the fix, the masked disc's outer ring came back as 0 m
  # (bare ground) and pulled wire_zone_cover below 1.
  r <- make_rasters(data.frame(x = numeric(), y = numeric(), h = numeric()))
  r$chm <- terra::setValues(r$chm, 9)
  pole <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(x0 + 50.5, y0 + 4.5)), crs = utm))
  rk <- risk_for(r, structures = pole, structure_mask_m = 4, tree_ws_m = 3)
  s <- sf::st_drop_geometry(rk$segments)
  expect_equal(s$wire_zone_cover[s$seg_id == 1], 1)
  expect_equal(s$wire_zone_cover[s$seg_id == 2], 1)
})

# A height-normalised LAS over a 60 x 40 m patch along the line y = y0:
# ground every 0.5 m, plus any above-ground points supplied.
make_las <- function(above = NULL, hole_x = NULL) {
  g <- expand.grid(X = x0 + seq(0, 60, 0.5), Y = y0 + seq(-20, 20, 0.5))
  pts <- data.frame(g, Z = 0, Classification = 2L)
  if (!is.null(above)) pts <- rbind(pts, data.frame(above, Classification = 1L))
  if (!is.null(hole_x)) pts <- pts[!(pts$X > x0 + hole_x[1] & pts$X < x0 + hole_x[2]), ]
  pts$ReturnNumber <- 1L
  pts$NumberOfReturns <- 1L
  pts$Intensity <- 100L
  las <- lidR::LAS(data.table::as.data.table(pts), crs = sf::st_crs(utm))
  lidR::normalize_height(las, lidR::tin())
}

pred_for <- function(las, label) {
  ag <- which(las$Classification != 2L)
  data.table::data.table(pid = ag, X = las$X[ag], Y = las$Y[ag], height_m = las$Z[ag],
                         pred = factor("vegetation", levels = label_levels),
                         label = factor(label(las$X[ag], las$Y[ag], las$Z[ag]), levels = label_levels))
}

segs60 <- function(seg_m) {
  ln <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(rbind(c(x0, y0), c(x0 + 60, y0))), crs = utm))
  segment_lines(ln, utm, seg_m = seg_m)
}

test_that("a LiDAR void is unobserved and its segment is 'no data', not 'none' (#4)", {
  set.seed(1)
  tree <- data.frame(X = x0 + 50 + runif(200, -1, 1), Y = y0 + 15 + runif(200, -1, 1), Z = runif(200, 2, 6))
  las <- make_las(tree, hole_x = c(20, 40))           # a missing tile, say
  r <- corridor_rasters(las, pred_for(las, function(x, y, z) "vegetation"))
  mid <- cbind(x0 + 30.25, y0 + 0.25)
  expect_false(is.na(terra::extract(r$dtm, mid)[, 1])) # the TIN bridges the hole...
  expect_true(terra::extract(r$unobserved, mid)[, 1] == 1) # ...but it is flagged
  expect_true(terra::extract(r$void, mid)[, 1] == 1)
  # ordinary 0.5 m point spacing never reads as a void
  expect_false(terra::extract(r$void, cbind(x0 + 10.25, y0 + 0.25))[, 1] == 1)

  s <- segs60(20)
  prof <- conductor_profile(no_wires, s, r$dtm, min_ground_clear_m = 10, attach_m = 10)
  rk <- sf::st_drop_geometry(assess_risk(r, prof, s, tree_ws_m = 3)$segments)
  rk <- rk[order(rk$seg_id), ]
  expect_equal(as.character(rk$priority), c("none", "no data", "none"))
  expect_equal(as.character(rk$priority_lo), c("none", "no data", "none"))
  expect_lt(rk$frac_observed[2], 0.5)
  expect_equal(rk$frac_observed[c(1, 3)], c(1, 1), tolerance = 0.01)
})

test_that("canopy left unlabelled beside a wire is unobserved, not bare ground (#6)", {
  set.seed(2)
  wire <- data.frame(X = x0 + seq(0, 60, 0.25), Y = y0 + 0.25, Z = 12)
  # a crown 1.5 m beside the wire, topping out 3 m below it: inside the
  # weak-label margin, so it is unlabelled (NA)
  crown <- data.frame(X = x0 + 45.25 + runif(60, -0.2, 0.2), Y = y0 + 1.75 + runif(60, -0.2, 0.2),
                      Z = runif(60, 2, 9))
  las <- make_las(rbind(wire, crown))
  lab <- function(x, y, z) ifelse(abs(y - (y0 + 0.25)) < 1e-6, "wire", NA)
  r <- corridor_rasters(las, pred_for(las, lab))
  at_crown <- cbind(x0 + 45.25, y0 + 1.75)
  expect_true(is.na(terra::extract(r$chm, at_crown)[, 1]))     # not in the canopy model
  expect_true(terra::extract(r$unobserved, at_crown)[, 1] == 1) # but unknown, not bare
  expect_false(terra::extract(r$void, at_crown)[, 1] == 1)
  # a wire-labelled cell has an observed air gap beneath it: it stays bare ground
  expect_false(terra::extract(r$unobserved, cbind(x0 + 10.1, y0 + 0.25))[, 1] == 1)
  expect_gte(r$n_uncertain_excluded, 60)

  s <- segs60(30)
  prof <- conductor_profile(no_wires, s, r$dtm, min_ground_clear_m = 12, attach_m = 12)
  rk <- sf::st_drop_geometry(assess_risk(r, prof, s, tree_ws_m = 3)$segments)
  rk <- rk[order(rk$seg_id), ]
  # the crown's cells drop out of the observed share of its segment only
  expect_equal(rk$frac_observed_under[1], 1, tolerance = 0.01)
  expect_lt(rk$frac_observed_under[2], 1)
})

test_that("low coverage turns 'none' into 'no data' but keeps real findings", {
  trees <- data.frame(x = x0 + 25.5, y = y0 + 0.5, h = 9) # grow-in in segment 1
  r <- make_rasters(trees)
  xy <- terra::crds(r$dtm, na.rm = FALSE)
  hide <- function(xmin, xmax) xy[, 1] > x0 + xmin & xy[, 1] < x0 + xmax & abs(xy[, 2] - y0) < 10
  r$unobserved <- terra::setValues(r$dtm, hide(40, 100) | hide(100, 160))
  s <- sf::st_drop_geometry(risk_for(r, tree_ws_m = 3)$segments)
  s <- s[order(s$seg_id), ]
  expect_equal(s$frac_observed, c(0.4, 0.4), tolerance = 0.02)
  expect_equal(as.character(s$priority), c("grow-in", "no data"))
  # full coverage leaves the tiers unchanged
  r$unobserved <- NULL
  s2 <- sf::st_drop_geometry(risk_for(r, tree_ws_m = 3)$segments)
  expect_equal(as.character(s2$priority[order(s2$seg_id)]), c("grow-in", "none"))
})

test_that("coverage counts structure footprints as observed and ignores cells past the line ends", {
  r <- make_rasters(data.frame(x = x0 + 150.5, y = y0 + 40.5, h = 4))
  # a line shorter than the raster: cells beyond its ends are not its corridor
  ln <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(rbind(c(x0 + 50, y0), c(x0 + 150, y0))), crs = utm))
  s <- segment_lines(ln, utm, seg_m = 50)
  prof <- conductor_profile(no_wires, s, r$dtm, min_ground_clear_m = 10, attach_m = 10)
  xy <- terra::crds(r$dtm, na.rm = FALSE)
  # the tower's own returns left the cell uncertain: unobserved in the rasters
  r$unobserved <- terra::setValues(r$dtm, abs(xy[, 1] - (x0 + 75)) < 6 & abs(xy[, 2] - y0) < 6)
  tower <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(x0 + 75, y0)), crs = utm))
  open <- sf::st_drop_geometry(assess_risk(r, prof, s)$segments)
  masked <- sf::st_drop_geometry(assess_risk(r, prof, s, structures = tower)$segments)
  open <- open[order(open$seg_id), ]
  masked <- masked[order(masked$seg_id), ]
  expect_equal(open$frac_observed[2], 1, tolerance = 0.01)  # past-the-end cells ignored
  expect_lt(open$frac_observed_under[1], 0.9)              # the gap counts...
  expect_gt(masked$frac_observed_under[1], 0.99)           # ...unless it is a known structure
})

test_that("'no data' under both bounds gets 'low coverage' and is drawn apart on the map", {
  r <- make_rasters(data.frame(x = x0 + 150.5, y = y0 + 40.5, h = 4))
  xy <- terra::crds(r$dtm, na.rm = FALSE)
  r$unobserved <- terra::setValues(r$dtm, xy[, 1] < x0 + 70 & abs(xy[, 2] - y0) < 10)
  rk <- risk_for(r, tree_ws_m = 3)
  s <- sf::st_drop_geometry(rk$segments)
  expect_equal(as.character(s$confidence[s$seg_id == 1]), "low coverage")
  expect_equal(as.character(s$priority_lo[s$seg_id == 1]), "no data")
  skip_if_not_installed("ggplot2")
  p <- plot_risk_map(r, rk)
  expect_s3_class(p, "ggplot")
  # (no strike trees here, so the shape scale warns about an empty layer)
  built <- suppressWarnings(ggplot2::ggplot_build(p))
  drawn <- unlist(lapply(built$plot$layers, function(l) {
    d <- l$data
    if (is.data.frame(d) && "certain" %in% names(d)) as.character(d$certain) else character()
  }))
  expect_true("insufficient LiDAR coverage" %in% drawn)
})

test_that("the midmod risk map dots 'no data' segments and ignores voids off the corridor", {
  skip_if_not_installed("ggplot2")
  withr::local_options(vegrisk.style = "midmod")
  r <- make_rasters(data.frame(x = x0 + 150.5, y = y0 + 5.5, h = 6))
  xy <- terra::crds(r$dtm, na.rm = FALSE)
  # a void under segment 1, plus off-corridor "voids" in the outer rows
  outside <- abs(xy[, 2] - y0) > 40 # beyond the corridor clip: no returns
  r$void <- terra::setValues(r$dtm, outside)
  r$unobserved <- terra::setValues(r$dtm, (xy[, 1] < x0 + 70 & abs(xy[, 2] - y0) < 10) | outside)
  rk <- risk_for(r, tree_ws_m = 3)
  built <- suppressWarnings(ggplot2::ggplot_build(plot_risk_map(r, rk)))
  sub <- built$plot$labels$subtitle
  expect_match(sub, "Dotted segments")
  # only the in-corridor void is counted: 70 x 20 cells, not the outer rows
  expect_match(sub, "1,400 m² unobserved")
  expect_no_match(sub, "on any segment")
  # the no-data segment is its own dotted layer, off the encroachment ramp
  i <- which(vapply(built$plot$layers, function(l) {
    d <- l$data
    !is.null(l$mapping$linetype) && is.data.frame(d) && nrow(d) > 0 &&
      all(d$certain == "insufficient LiDAR coverage")
  }, logical(1)))
  expect_length(i, 1)
  expect_true(all(built$data[[i]]$linetype == "11"))
})

test_that("no encroachment anywhere is drawn as absence, never on the risk ramp (#5)", {
  skip_if_not_installed("ggplot2")
  skip_if_not_installed("scales")
  pal <- vegrisk_palette()
  r <- make_rasters(data.frame(x = x0 + 150.5, y = y0 + 40.5, h = 4)) # nothing under the line
  rk <- risk_for(r, tree_ws_m = 3)
  expect_true(all(rk$segments$encroach_lo_m2 == 0))
  # Before the fix a free scale rescaled c(0, 0) to 0.5: mid-ramp for zero.
  built <- suppressWarnings(ggplot2::ggplot_build(plot_risk_map(r, rk)))
  cols <- unlist(lapply(built$data, `[[`, "colour"))
  expect_false(any(cols %in% pal$encroach))
  expect_true(any(vapply(built$data, function(d) nrow(d) == 2 && all(d$colour %in% pal$line), logical(1))))
  # With encroachment present, a shared upper limit can be imposed from outside.
  grow <- make_rasters(data.frame(x = x0 + 25.5, y = y0 + 0.5, h = 9))
  rk2 <- risk_for(grow, tree_ws_m = 3)
  expect_gt(max(rk2$segments$encroach_lo_m2), 0)
  built2 <- suppressWarnings(ggplot2::ggplot_build(plot_risk_map(grow, rk2, encroach_limits = c(0, 100))))
  expect_equal(built2$plot$scales$get_scales("colour")$limits, c(0, 100))
})

test_that("a mostly measured segment whose tier depends on the bound is bound-dependent (#14)", {
  # Conductor returns along the first 58 m of segment 1 at 10 m; a tree at
  # 80 m, in the unmeasured part, encroaches under the code-minimum bound
  # (5 m) but not under the optimistic one (20 m).
  r <- make_rasters(data.frame(x = x0 + 80.5, y = y0 + 0.5, h = 8))
  s <- segs()
  wires <- data.table::data.table(X = x0 + seq(0.25, 58, 0.5), Y = y0 + 0.3, height_m = 10,
                                  pred = factor("wire", levels = label_levels),
                                  label = factor("wire", levels = label_levels))
  prof <- conductor_profile(wires, s, r$dtm, min_ground_clear_m = 5, attach_m = 20, search_m = 15)
  rk <- sf::st_drop_geometry(assess_risk(r, prof, s, tree_ws_m = 3)$segments)
  rk <- rk[order(rk$seg_id), ]
  expect_gte(rk$frac_measured[1], 0.5)
  expect_equal(as.character(rk$priority_lo[1]), "grow-in")
  expect_equal(as.character(rk$priority[1]), "none")
  expect_equal(as.character(rk$confidence[1]), "bound-dependent")  # was "measured"
  expect_equal(as.character(rk$confidence[2]), "robust")
  # Tiers that agree on a mostly measured segment are still "measured".
  clear <- make_rasters(data.frame(x = numeric(), y = numeric(), h = numeric()))
  prof2 <- conductor_profile(wires, s, clear$dtm, min_ground_clear_m = 5, attach_m = 20, search_m = 15)
  rk2 <- sf::st_drop_geometry(assess_risk(clear, prof2, s, tree_ws_m = 3)$segments)
  expect_equal(as.character(rk2$confidence[rk2$seg_id == 1]), "measured")
})
