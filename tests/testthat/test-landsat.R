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
  d <- canopy_dryness(composite(), r, sc$profile, sc$risk, dry_quantile = 0.6)
  s <- sf::st_drop_geometry(d$segments)
  s <- s[order(s$seg_id), ]
  # Under-line pixels only (0.8, not the 0.6 woods beside the line); the
  # 1 m column at the shared segment vertex can fall either way.
  expect_equal(s$ndvi, c(0.8, 0.3), tolerance = 0.01)
  expect_equal(s$ndmi, c(0.5, 0.0), tolerance = 0.01)
  expect_true(all(s$canopy_m2 > 0))
  # Ranked against every canopy pixel: half the corridor is the 0.3 east.
  expect_gt(s$ndvi_pct[1], 0.7)
  expect_equal(s$ndvi_pct[2], 0.5, tolerance = 0.05)
  expect_identical(s$dry_canopy, c(FALSE, TRUE))
  expect_identical(s$dry_grow_in, c(FALSE, TRUE))
  expect_equal(attr(d$segments, "landsat")$dry_index, "ndvi")
  expect_true(all(d$pixels$scored))
})

test_that("pixels that are mostly cleared right-of-way are not scored", {
  # West half fully wooded; east half bare except a 3 m wide hedge under the line.
  r <- corridor(function(x, y) ifelse(x < x0 + 100 | abs(y - y0) < 1.5, 9, NA))
  sc <- screen(r)
  d <- canopy_dryness(composite(), r, sc$profile, sc$risk, min_canopy_frac = 0.5)
  s <- sf::st_drop_geometry(d$segments)
  s <- s[order(s$seg_id), ]
  expect_equal(s$ndvi[1], 0.8, tolerance = 1e-6)
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
  d <- canopy_dryness(composite(), r, sc$profile, sc$risk, min_canopy_frac = 0, min_ref_px = 1)
  s <- sf::st_drop_geometry(d$segments)
  s <- s[order(s$seg_id), ]
  expect_lt(s$canopy_m2[2], 5)
  expect_false(is.na(s$ndvi[2]))
  expect_true(is.na(s$ndvi_pct[2]))
  expect_true(is.na(s$dry_canopy[2]))
})

test_that("too few canopy pixels in the corridor leaves percentiles undefined", {
  r <- corridor(function(x, y) rep(9, length(x)))
  sc <- screen(r)
  d <- canopy_dryness(composite(), r, sc$profile, sc$risk, min_ref_px = 1000)
  expect_true(all(is.na(d$segments$ndvi_pct)))
  expect_true(all(!is.na(d$segments$ndvi)))
})
