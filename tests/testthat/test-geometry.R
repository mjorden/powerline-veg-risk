utm <- sf::st_crs(26913)

test_that("las_m_per_unit distinguishes metres from US survey feet", {
  expect_equal(las_m_per_unit(sf::st_sfc(sf::st_point(c(0, 0)), crs = 26913)), 1)
  expect_equal(las_m_per_unit(sf::st_sfc(sf::st_point(c(0, 0)), crs = 2263)), 1200 / 3937)
  expect_error(las_m_per_unit(sf::st_sfc(sf::st_point(c(0, 0)), crs = 4326)), "geographic")
})

test_that("line_corridor buffers in metres regardless of CRS units", {
  ln <- sf::st_sfc(sf::st_linestring(rbind(c(500000, 4400000), c(500100, 4400000))), crs = 26913)
  a_m <- as.numeric(sf::st_area(line_corridor(ln, 26913, half_width_m = 10)))
  expect_equal(a_m, 100 * 20, tolerance = 1e-6)
  ft <- line_corridor(ln, 2232, half_width_m = 10) # Colorado Central, ftUS
  expect_equal(as.numeric(units::set_units(sf::st_area(ft), "m^2")), 2000, tolerance = 0.01)
})

test_that("segment_lines covers the line with near-equal segments", {
  ln <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(500000, 4400000), c(500230, 4400000))), crs = utm))
  seg <- segment_lines(ln, utm, seg_m = 50)
  expect_equal(nrow(seg), 4)
  expect_equal(sum(seg$length_m), 230, tolerance = 1e-6)
  expect_true(all(abs(seg$length_m - 57.5) < 1e-6))
})

test_that("assign_blocks never splits a block across folds", {
  set.seed(3)
  feat <- data.table::data.table(X = runif(5000, 0, 1000), Y = runif(5000, 0, 1000))
  b <- assign_blocks(feat, utm, block_m = 100, n_folds = 5)
  expect_true(all(b[, data.table::uniqueN(fold), by = block]$V1 == 1))
  expect_setequal(unique(b$fold), 1:5)
  expect_equal(max(b$block), 100)
})

test_that("class_metrics computes precision, recall and F1", {
  df <- data.frame(
    truth = factor(c("vegetation", "vegetation", "wire", "wire"), levels = label_levels),
    pred  = factor(c("vegetation", "wire", "wire", "wire"), levels = label_levels)
  )
  m <- class_metrics(df, "x")
  w <- m[m$class == "wire", ]
  expect_equal(w$precision, 2 / 3)
  expect_equal(w$recall, 1)
  expect_equal(w$f1, 0.8)
})

test_that("avg_precision is 1 for a perfect ranking and ~prevalence for noise", {
  expect_equal(avg_precision(c(0.9, 0.8, 0.1, 0.05), c(TRUE, TRUE, FALSE, FALSE)), 1)
  set.seed(1)
  pos <- runif(20000) < 0.05
  expect_lt(abs(avg_precision(runif(20000), pos) - 0.05), 0.01)
  # weights stand in for subsampled negatives
  expect_equal(avg_precision(c(0.9, 0.1), c(TRUE, FALSE), w = c(1, 10)), 1)
})

test_that("avg_precision does not reward tied scores by row order", {
  set.seed(2)
  pos <- c(TRUE, rep(FALSE, 9999))
  score <- rep(0, 10000)
  expect_lt(avg_precision(score, pos), 0.001)
  expect_equal(avg_precision(score, rev(pos)), avg_precision(score, pos))
})

test_that("evaluate_vendor_classes maps ASPRS codes and ignores unclassified", {
  lab <- factor(c("vegetation", "vegetation", "building", "wire", "vegetation"), levels = label_levels)
  vc <- c(5L, 3L, 6L, 1L, 6L)
  ev <- evaluate_vendor_classes(lab, vc)
  v <- ev$metrics[ev$metrics$class == "vegetation", ]
  b <- ev$metrics[ev$metrics$class == "building", ]
  expect_equal(v$recall, 1)
  expect_equal(v$precision, 2 / 3)
  expect_equal(b$recall, 0.5)
  expect_equal(sum(ev$confusion), 4) # the unclassified (1) point is excluded
  expect_equal(v$balanced_accuracy, 0.75)
})

test_that("evaluate_vendor_classes exposes the majority-class baseline", {
  vc <- c(rep(5L, 98), 6L, 6L)
  ev <- evaluate_vendor_classes(factor(rep("vegetation", 100), levels = label_levels), vc)
  b <- ev$metrics[ev$metrics$class == "building", ]
  expect_equal(b$precision, 0)          # never predicted -> 0, not NA
  expect_equal(ev$metrics$kappa[1], 0)  # no skill
  expect_equal(ev$metrics, ev$baseline)
  expect_gt(ev$metrics$f1[1], 0.98)     # high vegetation F1 despite no skill
})
