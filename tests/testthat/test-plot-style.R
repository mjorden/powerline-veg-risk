test_that("midmod is the default style, classic is opt-in, unknown styles are rejected", {
  withr::local_options(vegrisk.style = NULL)
  expect_identical(vegrisk_style(), "midmod")
  withr::local_options(vegrisk.style = "classic")
  expect_identical(vegrisk_style(), "classic")
  withr::local_options(vegrisk.style = "art-deco")
  expect_error(vegrisk_style(), "classic")
})

test_that("both palettes fill the same roles and cover every point class", {
  classic <- vegrisk_palette("classic")
  midmod <- vegrisk_palette("midmod")
  expect_setequal(names(classic), names(midmod))
  for (pal in list(classic, midmod)) {
    expect_setequal(names(pal$classes), c(label_levels, "low", "ground"))
    expect_setequal(names(pal$schemes), c("random", "spatial_block", "spatial_ablation"))
  }
})

test_that("no plot function names a hex colour outside the palette", {
  fns <- ls(asNamespace("vegrisk"), pattern = "^plot_|_midmod$")
  hex <- vapply(fns, function(f) {
    grepl("#[0-9A-Fa-f]{6}", paste(deparse(get(f, asNamespace("vegrisk"))), collapse = "\n"))
  }, logical(1))
  expect_false(any(hex), label = paste(fns[hex], collapse = ", "))
})

test_that("a missing font falls back to the generic family", {
  expect_identical(vegrisk_font("No Such Font Family 123", "serif"), "serif")
})

cv_fixture <- function() {
  data.frame(scheme = rep(c("random", "spatial_block", "spatial_ablation"), each = 2),
             class = rep(c("vegetation", "wire"), 3), n = rep(c(1000, 4), 3),
             prevalence = rep(c(0.99, 0.004), 3),
             avg_precision = c(0.99, 0.4, 0.99, 0.004, 0.98, 0.003),
             recall = c(0.99, 0.2, 0.99, 0, 0.98, 0))
}

test_that("midmod plot_cv keys colours by scheme and keeps small AP visible (#34)", {
  skip_if_not_installed("ggplot2")
  withr::local_options(vegrisk.style = "midmod")
  pal <- vegrisk_palette("midmod")
  m <- cv_fixture()
  p <- plot_cv(m)
  expect_match(p$labels$title, "0.004 with spatial blocks", fixed = TRUE)
  # A subset of schemes keeps each scheme's own colour.
  sub <- m[m$scheme != "random", ]
  b <- ggplot2::ggplot_build(plot_cv(sub))
  pts <- b$data[[3]]
  expect_setequal(unique(pts$colour), unname(pal$schemes[c("spatial_block", "spatial_ablation")]))
  # Schemes in the same class row do not overlap.
  expect_equal(anyDuplicated(pts[, c("x", "y", "PANEL")]), 0)
  # Unknown schemes are kept, with a warning, instead of dropped.
  extra <- rbind(m, transform(m[m$scheme == "random", ], scheme = "buffered"))
  expect_warning(b2 <- ggplot2::ggplot_build(plot_cv(extra)), "buffered")
  expect_true(pal$neutral %in% b2$data[[3]]$colour)
  # n labels come from any scheme (classic takes them from spatial_block only).
  b3 <- ggplot2::ggplot_build(plot_cv(m[m$scheme == "random", ]))
  expect_false(any(grepl("NA", b3$layout$panel_params[[1]]$y$get_labels())))
  # No wire row (a corridor without wire labels) is not an error.
  nowire <- plot_cv(m[m$class != "wire", ])
  expect_identical(nowire$labels$title, "Cross-validated agreement with weak labels")
})

test_that("midmod risk map draws zero encroachment as absence, not risk (#5)", {
  skip_if_not_installed("ggplot2")
  withr::local_options(vegrisk.style = "midmod")
  utm <- sf::st_crs(26913)
  r <- terra::rast(xmin = 0, xmax = 100, ymin = -20, ymax = 20, resolution = 1, crs = "EPSG:26913")
  chm <- terra::setValues(r, ifelse(seq_len(terra::ncell(r)) %% 7 == 0, 5, NA))
  seg <- sf::st_sf(seg_id = 1:2, length_m = 50, encroach_lo_m2 = 0, confidence = "measured",
                   geometry = sf::st_sfc(sf::st_linestring(rbind(c(0, 0), c(50, 0))),
                                         sf::st_linestring(rbind(c(50, 0), c(100, 0))), crs = utm))
  trees <- sf::st_sf(strike = FALSE, strike_lo = FALSE, strike_hi = FALSE,
                     strike_possible = FALSE, strike_certain = FALSE,
                     geometry = sf::st_sfc(sf::st_point(c(10, 10)), crs = utm))
  p <- plot_risk_map(list(chm = chm, dtm = r), list(segments = seg, trees = trees))
  b <- ggplot2::ggplot_build(p)
  pal <- vegrisk_palette()
  # Both segments drawn in the neutral line colour (over the paper casing).
  expect_true(any(vapply(b$data, function(d) nrow(d) == 2 && all(d$colour %in% pal$line), logical(1))))
  expect_false(any(unlist(lapply(b$data, `[[`, "colour")) %in% pal$encroach))
  expect_match(p$labels$subtitle, "No canopy in the clearance envelope")
})
