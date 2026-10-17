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
