utm <- sf::st_crs(26913)
x0 <- 500000
y0 <- 4400000

test_that("canonical_crs() picks the NAD83(2011) UTM zone of the site", {
  co <- sf::st_sfc(sf::st_point(c(x0, y0)), crs = utm)          # about 105 W, zone 13
  expect_equal(canonical_crs(co)$epsg, 6342L)
  tn <- sf::st_sfc(sf::st_point(c(-86.9, 36.1)), crs = 4326)    # Nashville, zone 16
  expect_equal(canonical_crs(tn)$epsg, 6345L)
})

test_that("tree_ids() agree between a metre and a US-survey-feet delivery of the same point", {
  pts <- sf::st_sfc(sf::st_point(c(x0 + 10.3, y0 + 20.8)), sf::st_point(c(x0 + 11.1, y0 + 20.8)), crs = utm)
  ft <- sf::st_transform(pts, 2232)  # Colorado Central, ftUS
  id_m <- tree_ids(sf::st_coordinates(pts)[, 1:2], utm)
  id_ft <- tree_ids(sf::st_coordinates(ft)[, 1:2], sf::st_crs(2232))
  expect_equal(id_m, id_ft)
  expect_match(id_m[1], "^6342:")
  expect_false(id_m[1] == id_m[2])  # 0.8 m apart: different half-metre cells
})

test_that("match_trees() pairs epochs within a tolerance and keeps the unmatched", {
  a <- sf::st_sf(tree_id = c("a1", "a2"), height_m = c(10, 12),
                 geometry = sf::st_sfc(sf::st_point(c(x0, y0)), sf::st_point(c(x0 + 50, y0)), crs = utm))
  b <- sf::st_sf(tree_id = c("b1"), height_m = 11.5,
                 geometry = sf::st_sfc(sf::st_point(c(x0 + 0.8, y0 + 0.4)), crs = utm))
  mt <- match_trees(a, b, tol_m = 2)
  expect_equal(mt$id_b, c("b1", NA))
  expect_equal(mt$dh_m[1], 1.5)
  expect_lt(mt$distance_m[1], 1)
  expect_equal(nrow(match_trees(a, b[0, ])), 2)
})

test_that("line_structures() and line_spans() key spans on confirmed structures and flag long spans (#53)", {
  way <- sf::st_sf(osm_id = "w1", name = "Test", voltage_kv = 115,
                   geometry = sf::st_sfc(sf::st_linestring(rbind(
                     c(x0, y0), c(x0 + 200, y0 + 1), c(x0 + 400, y0), c(x0 + 1100, y0))), crs = utm))
  towers <- sf::st_sf(osm_id = c("n1", "n2", "n3"), type = "tower",
                      geometry = sf::st_sfc(sf::st_point(c(x0, y0)), sf::st_point(c(x0 + 400, y0)),
                                            sf::st_point(c(x0 + 1100, y0)), crs = utm))
  st <- line_structures(way, towers, utm)
  expect_equal(st$structure_id, c("Sn1", "Vw1:2", "Sn2", "Sn3"))
  expect_equal(st$confirmed, c(TRUE, FALSE, TRUE, TRUE))
  expect_equal(st$use, st$confirmed)
  expect_equal(st$s_m[3], 400, tolerance = 0.01)

  sp <- line_spans(way, towers, utm)
  expect_equal(sp$span_id, c("Sn1>Sn2", "Sn2>Sn3"))
  expect_equal(sp$length_m, c(400, 700), tolerance = 0.01)
  expect_equal(sp$implausible, c(FALSE, TRUE))   # 700 m on a 115 kV line: a missing structure
  expect_equal(sp$voltage_kv, c(115, 115))
  expect_equal(as.numeric(sf::st_length(sp)), sp$length_m, tolerance = 0.01)
  # A distribution line has the shorter plausible span.
  dist <- way; dist$voltage_kv <- 12.5
  expect_true(all(line_spans(dist, towers, utm)$implausible))
  # No tagged structures: every vertex, with a warning.
  expect_warning(bare <- line_spans(way, NULL, utm), "every vertex")
  expect_equal(nrow(bare), 3)
})

test_that("segments carry chainage along the way, not the clipped window (#53)", {
  way <- sf::st_sf(osm_id = "w1", geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(x0, y0), c(x0 + 1000, y0))), crs = utm))
  study <- sf::st_sf(osm_id = "w1", geometry = lwgeom::st_linesubstring(sf::st_geometry(way), 0.3, 0.5))
  seg <- segment_lines(study, utm, seg_m = 50, ways = way)
  expect_equal(seg$s_from_m[1], 0)
  expect_equal(seg$s_way_from_m[1], 300, tolerance = 0.01)
  expect_equal(max(seg$s_way_to_m), 500, tolerance = 0.01)
  expect_equal(seg$osm_id, rep("w1", nrow(seg)))
})

test_that("the profile's line ids follow the segments', whatever the union order (#53)", {
  south <- sf::st_linestring(rbind(c(x0, y0), c(x0 + 120, y0)))
  north <- sf::st_linestring(rbind(c(x0, y0 + 500), c(x0 + 120, y0 + 500)))
  ways <- sf::st_sf(osm_id = c("n", "s"), geometry = sf::st_sfc(north, south, crs = utm))
  seg <- segment_lines(ways, utm, seg_m = 50)
  r <- terra::rast(xmin = x0 - 10, xmax = x0 + 130, ymin = y0 - 10, ymax = y0 + 510, resolution = 5, crs = "EPSG:26913")
  dtm <- terra::setValues(r, 0)
  prof <- conductor_profile(data.table::data.table(X = numeric(), Y = numeric(), height_m = numeric(),
                                                   pred = factor(character(), levels = label_levels)),
                            seg, dtm, min_ground_clear_m = 5, attach_m = 10)
  by_seg <- tapply(prof$line_id, prof$seg_id, function(x) unique(x))
  expect_equal(as.vector(unlist(by_seg)), seg$line_id[match(as.integer(names(by_seg)), seg$seg_id)])
})

test_that("span_summary() rolls the stations up with the worst tier and summed counts (#53)", {
  way <- sf::st_sf(osm_id = "w1", geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(x0, y0), c(x0 + 100, y0), c(x0 + 200, y0))), crs = utm))
  towers <- sf::st_sf(osm_id = c("n1", "n2", "n3"), type = "tower",
                      geometry = sf::st_sfc(sf::st_point(c(x0, y0)), sf::st_point(c(x0 + 100, y0)),
                                            sf::st_point(c(x0 + 200, y0)), crs = utm))
  sp <- line_spans(way, towers, utm)
  seg <- segment_lines(way, utm, seg_m = 50, ways = way)   # 4 segments, 2 per span
  seg$priority <- factor(c("none", "fall-in", "none", "none"), levels = c("grow-in", "fall-in", "no data", "none"))
  seg$priority_lo <- factor(c("grow-in", "fall-in", "none", "none"), levels = c("grow-in", "fall-in", "no data", "none"))
  seg$confidence <- factor(c("robust", "bound-dependent", "measured", "measured"),
                           levels = c("measured", "robust", "bound-dependent", "low coverage"))
  seg$frac_measured <- c(0, 0.5, 1, 1); seg$frac_observed <- c(0.9, 1, 1, 0.95)
  seg$encroach_lo_m2 <- c(10, 0, 0, 0); seg$encroach_hi_m2 <- 0
  seg$min_clearance_lo_m <- c(1, 3, 8, 9); seg$min_clearance_hi_m <- c(6, 7, 8, 9)
  seg$n_strike_possible <- c(0, 2, 0, 1); seg$n_strike_certain <- c(0, 1, 0, 1)
  out <- span_summary(seg, sp, way)
  expect_equal(nrow(out), 2)
  expect_equal(out$n_segments, c(2L, 2L))
  expect_equal(as.character(out$priority), c("fall-in", "none"))
  expect_equal(as.character(out$priority_lo), c("grow-in", "none"))
  expect_equal(as.character(out$confidence), c("bound-dependent", "measured"))
  expect_equal(out$n_strike_possible, c(2, 1))
  expect_equal(out$encroach_lo_m2, c(10, 0))
  expect_equal(out$min_clearance_lo_m, c(1, 8))
  expect_equal(out$frac_measured, c(0.25, 1))
  expect_equal(attr(out, "segment_span")$span_id, c("Sn1>Sn2", "Sn1>Sn2", "Sn2>Sn3", "Sn2>Sn3"))
})
