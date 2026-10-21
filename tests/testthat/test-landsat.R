test_that("QA_PIXEL mask keeps clear land and drops cloud, shadow, snow, water, fill", {
  clear_land <- bitwShiftL(1L, 6L)            # bit 6 = clear
  expect_true(qa_clear(clear_land))
  expect_true(qa_clear(21824L))               # typical OLI clear-land value
  for (b in c(0:5, 7)) expect_false(qa_clear(clear_land + bitwShiftL(1L, b)), label = paste("bit", b))
  expect_true(qa_clear(clear_land + bitwShiftL(1L, 8L))) # cloud-confidence bits alone don't mask
  expect_identical(qa_clear(NA), NA)
})

test_that("surface reflectance scaling follows Collection 2 and drops invalid DNs", {
  expect_equal(sr_scale(c(7273, 43636)), c(0, 1), tolerance = 1e-4)
  expect_true(all(is.na(sr_scale(c(0, 7000, 50000)))))
  expect_equal(norm_diff(0.4, 0.1), 0.6)
})

test_that("STAC items parse into a scene table and incomplete items are dropped", {
  item <- function(id, assets = c("red", "nir08", "swir16", "qa_pixel")) list(
    id = id,
    properties = list(datetime = "2020-08-12T17:37:17.5Z", platform = "landsat-8", `eo:cloud_cover` = 10.4),
    assets = stats::setNames(lapply(assets, function(a) list(href = paste0("https://x/", id, "_", a, ".TIF"))), assets)
  )
  s <- parse_landsat_items(list(item("A"), item("B", assets = c("red", "nir08"))))
  expect_equal(nrow(s), 1)
  expect_equal(s$id, "A")
  expect_equal(s$swir1, "https://x/A_swir16.TIF")
  expect_equal(format(s$datetime, "%Y-%m-%d %H:%M"), "2020-08-12 17:37")
  expect_equal(month_days(2020, c(2, 9, 12)), c(29L, 30L, 31L))
})

# Synthetic corridor: E-W line along y = 0 with a 10 m conductor, two 100 m
# segments, and a 30 m "Landsat" composite whose east half is browner.
utm <- sf::st_crs(26913)
x0 <- 500000
y0 <- 4400000

corridor <- function(canopy_h) {
  r <- terra::rast(xmin = x0, xmax = x0 + 200, ymin = y0 - 50, ymax = y0 + 50,
                   resolution = 1, crs = "EPSG:26913")
  xy <- terra::crds(r, na.rm = FALSE)
  list(dtm = terra::setValues(r, 0), chm = terra::setValues(r, canopy_h(xy[, 1], xy[, 2])))
}

composite <- function(east_ndvi = 0.3, west_ndvi = 0.8, side_ndvi = 0.6) {
  # Pixel edges at x0 + 100 (the segment boundary) and y0 +/- 30: rows next
  # to the line are "under the conductors", the outer rows are woods beside
  # the right-of-way, which differ in the west.
  r <- terra::rast(xmin = x0 - 20, xmax = x0 + 250, ymin = y0 - 60, ymax = y0 + 60,
                   resolution = 30, crs = "EPSG:26913", nlyrs = 3)
  xy <- terra::crds(r, na.rm = FALSE)
  east <- xy[, 1] > x0 + 100
  ndvi <- ifelse(east, east_ndvi, ifelse(abs(xy[, 2] - y0) > 30, side_ndvi, west_ndvi))
  # A gentle west-to-east gradient (0.01 per pixel column) so the reference
  # distribution has spread: a two-valued composite ranks every segment mean
  # at a tie.
  ndvi <- ndvi + 0.01 * ((xy[, 1] - x0) %/% 30)
  r <- terra::setValues(r, cbind(ndvi, ndvi - 0.3, 8))
  names(r) <- c("ndvi", "ndmi", "n_obs")
  r
}

screen <- function(r) {
  ln <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(rbind(c(x0, y0), c(x0 + 200, y0))), crs = utm))
  s <- segment_lines(ln, utm, seg_m = 100)
  no_wires <- data.table::data.table(X = numeric(), Y = numeric(), height_m = numeric(),
                                     pred = factor(character(), levels = label_levels))
  prof <- conductor_profile(no_wires, s, r$dtm, min_ground_clear_m = 10, attach_m = 10)
  list(profile = prof, risk = assess_risk(r, prof, s, tree_ws_m = 3))
}

test_that("segment greenness comes from the grown-in canopy's pixels", {
  r <- corridor(function(x, y) rep(9, length(x))) # closed 9 m canopy: grow-in everywhere
  sc <- screen(r)
  d <- canopy_dryness(composite(), r, sc$profile, sc$risk, dry_quantile = 0.6, min_ref_px = 1)
  s <- sf::st_drop_geometry(d$segments)
  s <- s[order(s$seg_id), ]
  # Under-line pixels only (about 0.8, not the 0.6 woods beside the line);
  # the 1 m column at the shared segment vertex can fall either way.
  expect_true(s$ndvi[1] > 0.78 && s$ndvi[1] < 0.84)
  expect_true(s$ndvi[2] > 0.32 && s$ndvi[2] < 0.36)
  expect_equal(s$ndmi, s$ndvi - 0.3, tolerance = 1e-6)
  expect_true(all(s$canopy_m2 > 0))
  # Ranked against every scored pixel: the east half of the corridor is dry.
  expect_gt(s$ndvi_pct[1], 0.6)
  expect_lt(s$ndvi_pct[2], 0.5)
  expect_identical(s$dry_canopy, c(FALSE, TRUE))
  expect_identical(s$dry_grow_in, c(FALSE, TRUE))
  expect_equal(attr(d$segments, "landsat")$dry_index, "ndvi")
  # Pixels wholly inside the corridor are scored; those straddling the CHM
  # edge are mostly unobserved and are not.
  inside <- d$pixels$coverage >= 0.999
  expect_true(any(inside) && all(d$pixels$scored[inside]))
  expect_true(all(!d$pixels$scored[d$pixels$coverage < 0.8]))
})

test_that("pixels that are mostly cleared right-of-way are not scored", {
  # West half fully wooded; east half bare except a 3 m wide hedge under the line.
  r <- corridor(function(x, y) ifelse(x < x0 + 100 | abs(y - y0) < 1.5, 9, NA))
  sc <- screen(r)
  d <- canopy_dryness(composite(), r, sc$profile, sc$risk, min_canopy_frac = 0.5)
  s <- sf::st_drop_geometry(d$segments)
  s <- s[order(s$seg_id), ]
  expect_true(s$ndvi[1] > 0.78 && s$ndvi[1] < 0.84)
  expect_equal(s$canopy_px[2], 0)
  expect_true(is.na(s$ndvi[2]))
  expect_true(is.na(s$dry_canopy[2]))
})

test_that("cells beyond the corridor half-width don't count as bare ground", {
  # Bare ground everywhere except closed canopy within 15 m of the line; the
  # DTM covers the whole window, as a TIN does inside a bend.
  r <- corridor(function(x, y) ifelse(abs(y - y0) <= 15, 9, NA))
  sc <- screen(r)
  wide <- canopy_dryness(composite(), r, sc$profile, sc$risk, corridor_m = 50, min_ref_px = 1)
  tight <- canopy_dryness(composite(), r, sc$profile, sc$risk, corridor_m = 15, min_ref_px = 1)
  # Inner rows (|y| < 30): half canopy if the empty outer half counts as ground,
  # all canopy once it is excluded.
  inner <- function(d) d$pixels$canopy_frac[abs(sf::st_coordinates(d$pixels)[, 2] - y0) < 30]
  expect_true(all(inner(wide) < 0.6))
  expect_true(all(inner(tight) > 0.95))
  expect_true(all(abs(sf::st_coordinates(tight$pixels)[, 2] - y0) < 30))
  expect_equal(attr(tight$segments, "landsat")$corridor_m, 15)
})

test_that("a segment with only a few square metres of canopy gets no percentile", {
  r <- corridor(function(x, y) ifelse(x < x0 + 100 | (abs(y - y0) < 1 & abs(x - x0 - 150) < 1), 9, NA))
  sc <- screen(r)
  d <- canopy_dryness(composite(), r, sc$profile, sc$risk, min_canopy_frac = 0, min_ref_px = 1,
                      min_support = 0)
  s <- sf::st_drop_geometry(d$segments)
  s <- s[order(s$seg_id), ]
  expect_lt(s$canopy_m2[2], 5)
  expect_false(is.na(s$ndvi[2]))
  expect_true(is.na(s$ndvi_pct[2]))
  expect_true(is.na(s$dry_canopy[2]))
})

test_that("a mostly unobserved pixel is not scored, however green its sliver (#26)", {
  # Canopy only within 3 m of the line, bare elsewhere. With a 3 m corridor
  # each pixel row beside the line is 10% observed (3 of 30 cell rows); all
  # of that is canopy.
  r <- corridor(function(x, y) ifelse(abs(y - y0) <= 3, 9, NA))
  sc <- screen(r)
  tight <- canopy_dryness(composite(), r, sc$profile, sc$risk, corridor_m = 3, min_ref_px = 1)
  wide <- canopy_dryness(composite(), r, sc$profile, sc$risk, corridor_m = 50, min_ref_px = 1)
  rows <- function(d) abs(sf::st_coordinates(d$pixels)[, 2] - y0) < 30 &
    sf::st_coordinates(d$pixels)[, 1] > x0 + 10 & sf::st_coordinates(d$pixels)[, 1] < x0 + 190
  tp <- tight$pixels[rows(tight), ]
  expect_true(all(tp$canopy_frac > 0.95))        # the sliver is all canopy...
  expect_true(all(abs(tp$coverage - 0.1) < 0.02)) # ...but it is a sliver
  expect_false(any(tp$scored))
  wp <- wide$pixels[rows(wide), ]
  expect_true(all(abs(wp$coverage - 1) < 1e-6))
  expect_false(any(wp$scored))                    # 20% canopy: canopy-fraction gate
  g <- attr(tight$segments, "landsat")$n_px_excluded
  expect_gt(g[["coverage"]], 0)
})

test_that("structure surroundings are unknown, not canopy, and still count as observed (#26)", {
  r <- corridor(function(x, y) rep(9, length(x)))
  sc <- screen(r)
  pole <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(x0 + 50.5, y0 + 2.5)), crs = utm))
  plain <- canopy_dryness(composite(), r, sc$profile, sc$risk, min_ref_px = 1)
  masked <- canopy_dryness(composite(), r, sc$profile, sc$risk, min_ref_px = 1,
                           structures = pole, structure_mask_m = 8)
  s0 <- sf::st_drop_geometry(plain$segments)
  s1 <- sf::st_drop_geometry(masked$segments)
  expect_lt(s1$canopy_m2[s1$seg_id == 1], s0$canopy_m2[s0$seg_id == 1])
  expect_equal(s1$canopy_m2[s1$seg_id == 2], s0$canopy_m2[s0$seg_id == 2])
  inside <- masked$pixels$coverage >= 0.999
  expect_equal(sum(inside), sum(plain$pixels$coverage >= 0.999))
  expect_equal(attr(masked$segments, "landsat")$structure_mask_m, 8)
})

test_that("a one-cell spike is not canopy for the dryness weights (#26)", {
  r <- corridor(function(x, y) ifelse(x < x0 + 100, 9, NA))
  spike <- terra::cellFromXY(r$chm, cbind(x0 + 150.5, y0 + 0.5))
  r$chm[spike] <- 9
  sc <- screen(r)
  filtered <- canopy_dryness(composite(), r, sc$profile, sc$risk, min_canopy_frac = 0, min_ref_px = 1)
  raw <- canopy_dryness(composite(), r, sc$profile, sc$risk, min_canopy_frac = 0, min_ref_px = 1,
                        min_support = 0)
  px2 <- function(d) sf::st_drop_geometry(d$segments)$canopy_px[d$segments$seg_id == 2]
  expect_equal(px2(filtered), 0L)
  expect_equal(px2(raw), 1L)
})

test_that("a segment resting on one pixel keeps its index but gets no percentile (#26)", {
  # West half closed canopy; east half bare but for a 4 x 4 m block under
  # the line inside a single Landsat pixel (x 130-160, y 0-30).
  r <- corridor(function(x, y) ifelse(x < x0 + 100 | (x >= x0 + 140 & x < x0 + 144 & y >= y0 + 1 & y < y0 + 5), 9, NA))
  sc <- screen(r)
  one <- canopy_dryness(composite(), r, sc$profile, sc$risk, min_canopy_frac = 0, min_ref_px = 1)
  any_px <- canopy_dryness(composite(), r, sc$profile, sc$risk, min_canopy_frac = 0, min_ref_px = 1,
                           min_canopy_px = 1)
  s <- sf::st_drop_geometry(one$segments)
  s <- s[order(s$seg_id), ]
  expect_equal(s$canopy_px[2], 1L)
  expect_gte(s$canopy_m2[2], 5)
  expect_false(is.na(s$ndvi[2]))
  expect_true(is.na(s$ndvi_pct[2]))
  s2 <- sf::st_drop_geometry(any_px$segments)
  expect_false(is.na(s2$ndvi_pct[s2$seg_id == 2]))
})

test_that("pixels with too few clear observations are not scored (#26)", {
  r <- corridor(function(x, y) rep(9, length(x)))
  sc <- screen(r)
  d <- canopy_dryness(composite(), r, sc$profile, sc$risk, min_ref_px = 1, min_obs = 9) # n_obs is 8
  expect_false(any(d$pixels$scored))
  expect_equal(attr(d$segments, "landsat")$n_px_excluded[["n_obs"]], nrow(d$pixels))
  expect_true(all(is.na(d$segments$ndvi)))
})

test_that("too few canopy pixels in the corridor leaves percentiles undefined", {
  r <- corridor(function(x, y) rep(9, length(x)))
  sc <- screen(r)
  d <- canopy_dryness(composite(), r, sc$profile, sc$risk, min_ref_px = 1000)
  expect_true(all(is.na(d$segments$ndvi_pct)))
  expect_true(all(!is.na(d$segments$ndvi)))
})

test_that("landsat_composite logs every scene, with no-coverage apart from read errors (#30)", {
  scenes <- tibble::tibble(id = c("A", "B", "C", "D"),
                           datetime = as.POSIXct("2020-08-01", tz = "UTC") + 86400 * 0:3,
                           platform = "landsat-8", cloud_cover = 5,
                           red = "r", nir = "n", swir1 = "s", qa = "q")
  tile <- function(v) {
    r <- terra::rast(xmin = x0, xmax = x0 + 90, ymin = y0, ymax = y0 + 90, resolution = 30,
                     crs = "EPSG:26913", nlyrs = 2, vals = v)
    names(r) <- c("ndvi", "ndmi")
    r
  }
  testthat::local_mocked_bindings(read_landsat_window = function(sc, aoi, buffer_m, template = NULL) {
    switch(sc$id,
           A = tile(0.5),
           B = rlang::abort("scene does not cover the AOI"),
           C = rlang::abort("HTTP 503 from /vsicurl"),
           D = tile(0.7))
  })
  aoi <- sf::st_as_sfc(sf::st_bbox(c(xmin = x0, xmax = x0 + 90, ymin = y0, ymax = y0 + 90), crs = utm))
  expect_warning(expect_warning(comp <- landsat_composite(scenes, aoi), "Skipping Landsat scene B"),
                 "Skipping Landsat scene C")
  expect_equal(attr(comp, "scenes"), c("A", "D"))
  log <- attr(comp, "scene_log")
  expect_equal(log$id, c("A", "B", "C", "D"))
  expect_equal(log$used, c(TRUE, FALSE, FALSE, TRUE))
  expect_equal(log$skip_reason, c(NA, "no coverage", "HTTP 503 from /vsicurl", NA))
  expect_equal(unname(terra::values(comp$n_obs)[1]), 2)
})
