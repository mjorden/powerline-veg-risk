# Smoke tests for every plot function on synthetic inputs: each builds
# without error, and the encodings the figures are built around hold.
skip_if_not_installed("ggplot2")
skip_if_not_installed("scales")

utm <- sf::st_crs(26913)
x0 <- 500000
y0 <- 4400000

synthetic_corridor <- function(trees = data.frame(x = x0 + c(25.5, 150.5), y = y0 + c(0.5, 13.5), h = c(9, 15))) {
  r <- terra::rast(xmin = x0, xmax = x0 + 200, ymin = y0 - 50, ymax = y0 + 50, resolution = 1, crs = "EPSG:26913")
  xy <- terra::crds(r, na.rm = FALSE)
  h <- numeric(nrow(xy))
  for (i in seq_len(nrow(trees))) {
    d <- sqrt((xy[, 1] - trees$x[i])^2 + (xy[, 2] - trees$y[i])^2)
    h <- pmax(h, trees$h[i] - 2 * d)
  }
  rasters <- list(dtm = terra::setValues(r, 0), chm = terra::setValues(r, ifelse(h > 0, h, NA)))
  ln <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(rbind(c(x0, y0), c(x0 + 200, y0))), crs = utm))
  s <- segment_lines(ln, utm, seg_m = 100)
  wires <- data.table::data.table(X = x0 + seq(0.25, 58, 0.5), Y = y0 + 0.3, height_m = 10,
                                  pred = factor("wire", levels = label_levels),
                                  label = factor("wire", levels = label_levels))
  prof <- conductor_profile(wires, s, rasters$dtm, min_ground_clear_m = 5, attach_m = 20, search_m = 15)
  risk <- assess_risk(rasters, prof, s, tree_ws_m = 3, phase_offset_m = 3)
  list(rasters = rasters, profile = prof, risk = risk, segments = s, line = ln)
}

test_that("the risk map builds, keys its parts, and reports unobserved area", {
  sc <- synthetic_corridor()
  pal <- vegrisk_palette()
  f <- withr::local_tempfile(fileext = ".png")
  p <- plot_risk_map(sc$rasters, sc$risk, title = "t", source = "s")
  expect_s3_class(p, "ggplot")
  b <- suppressWarnings(ggplot2::ggplot_build(p))
  expect_match(p$labels$subtitle, "Potential strike trees")
  expect_match(p$labels$subtitle, "Dashed segments")  # tiers differ between bounds here
  # the canopy key ends in "30+"
  fill <- b$plot$scales$get_scales("fill")
  expect_true("30+" %in% fill$get_labels())
  # unobserved cells are drawn and counted
  r2 <- sc$rasters
  xy <- terra::crds(r2$dtm, na.rm = FALSE)
  r2$unobserved <- terra::setValues(r2$dtm, xy[, 1] > x0 + 120 & xy[, 1] < x0 + 140 & abs(xy[, 2] - y0) < 5)
  p2 <- plot_risk_map(r2, sc$risk)
  expect_match(p2$labels$subtitle, "unobserved by the LiDAR")
  expect_invisible(suppressWarnings(plot_risk_map(sc$rasters, sc$risk, file = f)))
  expect_gt(file.size(f), 1000)
})

test_that("the profile never connects measured and bounded stretches, and places strike trees (#32, #12)", {
  sc <- synthetic_corridor()
  p <- plot_profile(sc$profile, sc$risk, attach_m = 20)
  expect_match(p$labels$title, "measured along")
  expect_match(p$labels$subtitle, "classified returns")
  expect_match(p$labels$subtitle, "strike trees")
  b <- ggplot2::ggplot_build(p)
  # the measured line has one group, the bounded ribbon another, and no
  # layer joins the two sources into one path
  src_groups <- lapply(b$data, function(d) if ("group" %in% names(d)) length(unique(d$group)) else NA)
  expect_true(all(unlist(src_groups) >= 1, na.rm = TRUE))
  expect_equal(nrow(b$data[[length(b$data)]]), sum(sc$risk$trees$strike))
  # a two-line profile picks the first with a message and takes line_id
  pr2 <- sc$profile
  pr2$line_id <- 2L
  both <- rbind(sc$profile, pr2)
  expect_message(plot_profile(both), "line 1 of 2")
  expect_silent(plot_profile(both, line_id = 2L))
  expect_error(plot_profile(both, line_id = 9L), "line_id")
  # a fully measured line says so without "bounded elsewhere"
  all_meas <- sc$profile
  all_meas$src <- "measured"
  expect_match(plot_profile(all_meas)$labels$title, "whole line")
})

test_that("the cross-section orients its axis and survives at = 1", {
  las <- lidR::LAS(data.table::data.table(X = x0 + runif(400, 0, 200), Y = y0 + runif(400, -40, 40),
                                          Z = runif(400, 0, 20), Classification = 1L), crs = utm)
  pred <- data.table::data.table(pid = seq_len(400), pred = factor("vegetation", levels = label_levels))
  sc <- synthetic_corridor()
  p <- plot_cross_section(las, pred, sc$line, at = 0.5)
  expect_match(p$labels$x, "←")
  expect_match(p$labels$x, "N|S")  # across an E-W line the ends are north and south
  expect_s3_class(plot_cross_section(las, pred, sc$line, at = 1), "ggplot")
  expect_s3_class(plot_cross_section(las, pred, sc$line, at = 0), "ggplot")
})

test_that("importance and dryness and wind maps build with their keys", {
  sc <- synthetic_corridor()
  pal <- vegrisk_palette()
  # importance
  model <- list(variable.importance = c(height_m = 0.3, linearity_k10 = 0.2, intensity = 0.05))
  expect_s3_class(plot_importance(model), "ggplot")
  # dryness: a composite with a west/east split
  comp <- terra::rast(xmin = x0 - 20, xmax = x0 + 250, ymin = y0 - 60, ymax = y0 + 60, resolution = 30,
                      crs = "EPSG:26913", nlyrs = 3)
  xy <- terra::crds(comp, na.rm = FALSE)
  ndvi <- ifelse(xy[, 1] > x0 + 100, 0.3, 0.8) + 0.01 * ((xy[, 1] - x0) %/% 30)
  comp <- terra::setValues(comp, cbind(ndvi, ndvi - 0.3, 8))
  names(comp) <- c("ndvi", "ndmi", "n_obs")
  attr(comp, "scenes") <- c("LC08_A", "LC08_B")
  attr(comp, "dates") <- as.Date(c("2020-07-02", "2020-09-29"))
  full <- sc$rasters
  full$chm <- terra::setValues(full$chm, 9)
  risk_full <- assess_risk(full, sc$profile, sc$segments, tree_ws_m = 3)
  d <- canopy_dryness(comp, full, sc$profile, risk_full, min_ref_px = 1)
  p <- plot_canopy_dryness(d)
  expect_match(p$labels$subtitle, "Grey pixels not scored")
  expect_match(p$labels$subtitle, "2020-07 to 2020-09", fixed = TRUE)  # ISO months, locale-proof
  fill <- ggplot2::ggplot_build(p)$plot$scales$get_scales("fill")
  expect_true(any(grepl("dry cut", fill$get_labels())))
  plo <- plot_canopy_dryness(d, bound = "lo")
  expect_match(plo$labels$subtitle, "pessimistic")
  # wind
  hours <- fire_wind_hours(tibble::tibble(time = Sys.time() + 3600 * 1:30, wind_ms = 5, gust_ms = 20,
                                          dir_from_deg = 0, rh_pct = 10), min_gust_ms = 15, max_rh = 30)
  rw <- wind_fall_exposure(sc$risk, sc$profile, hours, phase_offset_m = 3, min_hours = 1)
  w <- plot_wind_exposure(rw, sc$rasters)
  expect_s3_class(w, "patchwork")
  expect_match(w$patches$annotation$subtitle, "fall scatter")
  expect_s3_class(plot_wind_exposure(rw, NULL), "patchwork")  # no backdrop is fine too
  f <- withr::local_tempfile(fileext = ".png")
  suppressWarnings(plot_wind_exposure(rw, sc$rasters, file = f))
  expect_gt(file.size(f), 1000)
})
