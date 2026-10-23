utm <- sf::st_crs(26913)

test_that("las_file_info() records identity and header fields without reading points", {
  f <- system.file("extdata", "MixedConifer.laz", package = "lidR")
  info <- las_file_info(f)
  expect_equal(nrow(info), 1)
  expect_equal(info$file, "MixedConifer.laz")
  expect_equal(info$md5, unname(tools::md5sum(f)))
  expect_equal(info$bytes, file.size(f))
  expect_gt(info$n_points, 1000)
  expect_true(info$gps_time_type %in% c("adjusted_standard", "gps_week"))
  expect_true(grepl("^1\\.[0-4]$", info$las_version))
})

test_that("lidar_vintage() converts adjusted standard GPS time to UTC and refuses week time", {
  # 2020-05-29 14:25 UTC is 274797515 s of adjusted standard GPS time
  # (seconds since 1980-01-06 minus 1e9, leap seconds ignored).
  pts <- data.frame(X = 500000 + runif(50), Y = 4400000 + runif(50), Z = runif(50, 0, 5),
                    gpstime = 274797515 + seq(0, 2316, length.out = 50))
  las <- lidR::LAS(pts, crs = utm)
  las@header@PHB[["Global Encoding"]][["GPS Time Type"]] <- TRUE
  v <- lidar_vintage(las)
  expect_equal(v$gps_time_type, "adjusted_standard")
  expect_equal(v$n, 50)
  expect_equal(format(v$from, "%Y-%m-%d %H:%M", tz = "UTC"), "2020-05-29 14:25")
  expect_equal(format(v$to, "%Y-%m-%d %H:%M", tz = "UTC"), "2020-05-29 15:03")
  expect_length(v$time, 50)

  las@header@PHB[["Global Encoding"]][["GPS Time Type"]] <- FALSE
  expect_warning(w <- lidar_vintage(las), "week")
  expect_true(is.na(w$from))
  expect_null(w$time)

  # No gpstime attribute at all: NA, not an error.
  bare <- lidR::LAS(pts[, c("X", "Y", "Z")], crs = utm)
  expect_true(is.na(lidar_vintage(bare)$from))
})

test_that("segment_flight_window() summarises per segment and survives all-NA input", {
  t0 <- as.POSIXct("2020-05-29 14:00", tz = "UTC")
  fw <- segment_flight_window(t0 + c(0, 60, 120, 600, 660), c(1L, 1L, 1L, 2L, 2L))
  expect_equal(fw$seg_id, 1:2)
  expect_equal(fw$n_timed, c(3L, 2L))
  expect_equal(fw$flight_median[1], t0 + 60)
  expect_equal(fw$flight_to[2], t0 + 660)
  empty <- segment_flight_window(as.POSIXct(c(NA, NA), tz = "UTC"), c(1L, 2L))
  expect_equal(nrow(empty), 0)
  expect_true(all(c("flight_from", "flight_median", "flight_to", "n_timed") %in% names(empty)))
})

test_that("read_corridor() keeps the GPS time attribute (#52)", {
  f <- system.file("extdata", "MixedConifer.laz", package = "lidR")
  h <- lidR::readLASheader(f)
  bb <- sf::st_bbox(h)
  ln <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(rbind(
    c(bb[["xmin"]] + 10, mean(bb[c("ymin", "ymax")])), c(bb[["xmax"]] - 10, mean(bb[c("ymin", "ymax")])))),
    crs = sf::st_crs(h)))
  las <- read_corridor(f, ln, half_width_m = 20)
  expect_true("gpstime" %in% names(las@data))
})
