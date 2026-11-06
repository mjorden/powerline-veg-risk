utm <- sf::st_crs(26913)
x0 <- 500000
y0 <- 4400000

# A 400 m diagonal corridor: ground every 0.5 m within 15 m of the line,
# one 12 m tree beside it. The bounding box is a 283 m square; the corridor
# is a thin strip across it.
diagonal_las <- function() {
  set.seed(5)
  s <- seq(0, 400, 0.5)
  off <- seq(-15, 15, 0.5)
  g <- expand.grid(s = s, o = off)
  u <- c(1, 1) / sqrt(2)
  pts <- data.frame(X = x0 + g$s * u[1] - g$o * u[2], Y = y0 + g$s * u[1] + g$o * u[2], Z = 0, Classification = 2L)
  tree <- data.frame(X = x0 + 200 * u[1] - 10 * u[2] + runif(300, -1.5, 1.5),
                     Y = y0 + 200 * u[1] + 10 * u[2] + runif(300, -1.5, 1.5), Z = runif(300, 2, 12), Classification = 1L)
  pts <- rbind(pts, tree)
  pts$ReturnNumber <- 1L; pts$NumberOfReturns <- 1L; pts$Intensity <- 100L
  las <- lidR::LAS(data.table::as.data.table(pts), crs = utm)
  lidR::normalize_height(las, lidR::tin())
}

test_that("rasters are masked to the corridor and cell tables scale with it, not the bounding box (#55)", {
  las <- diagonal_las()
  ln <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(rbind(c(x0, y0), c(x0 + 400 / sqrt(2), y0 + 400 / sqrt(2)))),
                                        crs = utm))
  corridor <- line_corridor(ln, utm, half_width_m = 15)
  feat <- point_features(las, k = c(10L, 20L))
  pred <- data.table::copy(feat)
  pred[, `:=`(pred = factor("vegetation", levels = label_levels), label = factor("vegetation", levels = label_levels))]
  r <- corridor_rasters(las, pred, corridor = corridor)
  n_all <- terra::ncell(r$dtm)
  n_in <- terra::global(!is.na(r$dtm), "sum", na.rm = TRUE)[[1]]
  expect_lt(n_in, 0.3 * n_all)                       # the strip, not the square
  expect_equal(terra::ncell(r$chm), n_all)           # one grid for every raster
  s <- segment_lines(ln, utm, seg_m = 100)
  prof <- conductor_profile(data.table::data.table(X = numeric(), Y = numeric(), height_m = numeric(),
                                                   pred = factor(character(), levels = label_levels)),
                            s, r$dtm, min_ground_clear_m = 8, attach_m = 8)
  rk <- assess_risk(r, prof, s, tree_ws_m = 3, coverage_m = 15, wire_zone_m = 15)
  expect_lt(attr(rk$segments, "n_cells_band"), 0.3 * n_all)
  expect_gte(nrow(rk$trees), 1)
  expect_true(all(rk$segments$frac_observed > 0.9))   # the strip is seen end to end
})

test_that("the features table carries elevation and class, so nothing indexes the cloud by row (#55)", {
  las <- diagonal_las()
  feat <- point_features(las, k = c(10L, 20L))
  expect_true(all(c("Zref", "class_code", "gpstime") %in% names(feat)))
  expect_false(any(c("Zref", "class_code", "gpstime") %in% attr(feat, "features")))
  expect_equal(feat$Zref, las$Zref[feat$pid])
  expect_true(all(feat$class_code == 1L))
  pred <- data.table::copy(feat)
  pred[, `:=`(pred = factor("vegetation", levels = label_levels), label = factor("vegetation", levels = label_levels))]
  pred[, pid := NULL]                                  # no row index at all
  r <- corridor_rasters(las, pred)
  expect_gt(terra::global(r$chm, "max", na.rm = TRUE)[[1]], 8)
})

test_that("corridor_rasters() refuses a table featurised from another point cloud (#55)", {
  las <- diagonal_las()
  feat <- point_features(las, k = c(10L, 20L))
  pred <- data.table::copy(feat)
  pred[, `:=`(pred = factor("vegetation", levels = label_levels), label = factor("vegetation", levels = label_levels))]
  other <- lidR::filter_poi(las, X < x0 + 200)
  expect_error(corridor_rasters(other, pred), "different point cloud")
})

test_that("min_reach() gives the same answer in chunks and with a capped k", {
  prof <- data.frame(line_id = 1, x = x0 + 0:300, y = y0, s_m = 0:300, tx = 1, ty = 0, ground = 0,
                     z_lo = 10, z_hi = 20)
  set.seed(2)
  xy <- cbind(x0 + runif(50, 0, 300), y0 + runif(50, 5, 25))
  g <- runif(50, -3, 3)
  h <- runif(50, 10, 25)
  a <- vegrisk:::min_reach(xy, g, prof$z_lo, prof, 1, 3, h)
  b <- vegrisk:::min_reach(xy, g, prof$z_lo, prof, 1, 3, h, chunk = 7L)
  expect_equal(a$reach, b$reach)
  expect_equal(a$dz, b$dz)
  capped <- vegrisk:::min_reach(xy, g, prof$z_lo, prof, 1, 3, h, max_k = 20L)
  expect_equal(capped$reach, a$reach, tolerance = 1e-9)   # 20 vertices still cover a 25 m reach
})
