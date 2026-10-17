utm <- sf::st_crs(26913)
x0 <- 500000
y0 <- 4400000

line <- sf::st_sf(geometry = sf::st_sfc(
  sf::st_linestring(rbind(c(x0, y0), c(x0 + 100, y0))), crs = utm))

synthetic_feat <- function() {
  # Wire: a thin layer at 11.8-12.2 m directly over the line, nothing below.
  wire <- data.frame(X = x0 + seq(0.25, 99.75, 0.5), Y = y0 + 0.3,
                     height_m = 12 + rep(c(-0.2, 0.2), 100))
  # Tree 25 m from the line: returns from 2 m to 15 m in the same columns.
  tree <- expand.grid(X = x0 + 50 + c(0.2, 0.7), Y = y0 + 25 + c(0.2, 0.7),
                      height_m = seq(2, 15, 0.5))
  # Tree crown 1 m beside the wire: inside the ambiguity margin.
  edge <- data.frame(X = x0 + 30.5, Y = y0 + 2.1, height_m = seq(2, 14, 1))
  # Building roof 30 m from the line.
  roof <- expand.grid(X = x0 + 70 + 0:4, Y = y0 - 30 - 0:4, height_m = 6)
  d <- data.table::as.data.table(rbind(wire, tree, edge, roof))
  d[, Z := height_m]
  d[, part := rep(c("wire", "tree", "edge", "roof"),
                  c(nrow(wire), nrow(tree), nrow(edge), nrow(roof)))]
  d[]
}

test_that("weak_labels separates suspended wire, trees, roofs and margins", {
  feat <- synthetic_feat()
  bld <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(x0 + 68, y0 - 36), c(x0 + 76, y0 - 36), c(x0 + 76, y0 - 28),
    c(x0 + 68, y0 - 28), c(x0 + 68, y0 - 36)))), crs = utm))
  lab <- weak_labels(feat, utm, line, structures = NULL, buildings = bld)

  expect_true(all(lab$label[lab$part == "wire"] == "wire"))
  expect_true(all(lab$label[lab$part == "tree"] == "vegetation"))
  expect_true(all(lab$label[lab$part == "roof"] == "building"))
  expect_true(all(is.na(lab$label[lab$part == "edge"])))
})

test_that("suspended points far from any mapped line are not labelled wire", {
  feat <- synthetic_feat()
  far_line <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(x0, y0 + 500), c(x0 + 100, y0 + 500))), crs = utm))
  lab <- weak_labels(feat, utm, far_line)
  expect_false(any(lab$label == "wire", na.rm = TRUE))
})

test_that("three parallel phases are labelled wire; a crown blob abstains", {
  phases <- data.table::rbindlist(lapply(c(-3, 0, 3), function(o) {
    data.table::data.table(X = x0 + seq(0.25, 99.75, 0.5), Y = y0 + o + 0.5, height_m = 12)
  }))
  # Elevated crown, 6 m across, beside the line with nothing beneath it.
  blob <- data.table::as.data.table(expand.grid(X = x0 + 70 + seq(0.25, 5.75, 0.5),
                                                Y = y0 + 6 + seq(0.25, 5.75, 0.5),
                                                height_m = c(9, 10)))
  feat <- rbind(phases[, part := "phase"], blob[, part := "blob"])
  feat[, Z := height_m]
  lab <- weak_labels(feat, utm, line)
  expect_true(all(lab$label[lab$part == "phase"] == "wire"))
  expect_true(all(is.na(lab$label[lab$part == "blob"])))
})

test_that("point_features returns finite features for above-ground points", {
  las <- lidR::readLAS(system.file("extdata", "MixedConifer.laz", package = "lidR"),
                       select = "xyzirnc")
  feat <- point_features(las, k = c(10L, 20L))
  expect_equal(nrow(feat), sum(las$Z >= 2 & las$Classification != 2L))
  fc <- feature_columns(feat)
  expect_true(all(c("linearity_k10", "planarity_k20", "intensity") %in% fc))
  expect_true(all(vapply(feat[, fc, with = FALSE], function(v) all(is.finite(v)), TRUE)))
  expect_true(all(feat$intensity > 0 & feat$intensity < 1))
})
