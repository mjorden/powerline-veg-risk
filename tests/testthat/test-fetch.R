# Request plumbing and parsers, all offline.

test_that("every request carries the user agent, a timeout and transient retries (#16)", {
  req <- vegrisk_request("https://example.org/api", timeout_s = 42, max_tries = 5)
  expect_match(req$options$useragent, "vegrisk R package")
  expect_equal(req$options$timeout_ms, 42000)
  expect_equal(req$policies$retry_max_tries, 5)
  expect_true(isTRUE(req$policies$retry_on_failure))
  is_transient <- req$policies$retry_is_transient
  fake <- function(status) httr2::response(status_code = status)
  expect_true(all(vapply(c(429L, 502L, 503L, 504L), function(s) is_transient(fake(s)), TRUE)))
  expect_false(is_transient(fake(404L)))
  expect_false(is_transient(fake(200L)))
})

test_that("an Overpass answer with a remark is refused, not treated as empty (#8)", {
  body <- list(osm3s = list(timestamp_osm_base = "2026-10-01T00:00:00Z"),
               remark = "runtime error: Query timed out in \"query\" at line 1 after 90 seconds.",
               elements = list())
  expect_error(overpass_elements(body, "q"), "did not complete")
  ok <- list(osm3s = list(timestamp_osm_base = "2026-10-01T00:00:00Z"),
             elements = list(list(id = 1, lat = 40, lon = -105, tags = list(power = "tower"))))
  els <- overpass_elements(ok, "q")
  expect_length(els, 1)
  expect_equal(attr(els, "osm_timestamp"), "2026-10-01T00:00:00Z")
  expect_equal(attr(els, "osm_query"), "q")
  # No elements key at all (nothing matched) is an empty list, not NULL.
  none <- overpass_elements(list(osm3s = list(timestamp_osm_base = "t")), "q")
  expect_identical(length(none), 0L)
  expect_equal(attr(none, "osm_timestamp"), "t")
})

test_that("empty OSM layers are well-formed sf objects with the right columns and CRS (#8)", {
  # sf cannot type a zero-feature geometry column, so the contract is: zero
  # rows, the documented attribute columns, EPSG:4326, and rbind-able.
  pts <- sf::st_sf(osm_id = character(), type = character(), geometry = empty_sfc("POINT"))
  pol <- sf::st_sf(osm_id = character(), geometry = empty_sfc("POLYGON"))
  expect_equal(nrow(pts), 0)
  expect_equal(names(pts), c("osm_id", "type", "geometry"))
  expect_equal(names(pol), c("osm_id", "geometry"))
  expect_equal(sf::st_crs(pts)$epsg, 4326)
  expect_equal(sf::st_crs(pol)$epsg, 4326)
  one <- sf::st_sf(osm_id = "1", type = "tower", geometry = sf::st_sfc(sf::st_point(c(-105, 40)), crs = 4326))
  both <- rbind(pts, one)
  expect_equal(nrow(both), 1)
  expect_s3_class(sf::st_geometry(both), "sfc_POINT")
  expect_error(empty_sfc("CIRCLE"))
})

test_that("a project filter that matches nothing aborts and names what was found (#16)", {
  tiles <- sf::st_sf(
    title = c("USGS Lidar Point Cloud CO_DRCOG_2020_B20 w0472n4429", "USGS Lidar Point Cloud CO_Eastern_2018 w0472n4429"),
    url = c("a", "b"), size_mb = c(1, 1), size_bytes = c(1e6, 1e6), pub_date = as.Date(c("2021-01-01", "2019-01-01")),
    geometry = sf::st_sfc(sf::st_point(c(0, 0)), sf::st_point(c(0, 0)), crs = 4326))
  expect_equal(nrow(filter_tiles(tiles, "DRCOG")), 1)
  expect_equal(nrow(filter_tiles(tiles, NULL)), 2)
  expect_error(filter_tiles(tiles, "CO_DRC0G"), "CO_DRCOG_2020_B20")
})

test_that("a tile counts as complete only at the size TNM reported (#16)", {
  f <- withr::local_tempfile(fileext = ".laz")
  expect_false(tile_complete(f, 10))            # absent
  writeBin(raw(10), f)
  expect_true(tile_complete(f, 10))
  expect_false(tile_complete(f, 20))            # interrupted download
  expect_true(tile_complete(f, NA))             # size unknown: non-empty is enough
  writeBin(raw(0), f)
  expect_false(tile_complete(f, NA))            # empty never counts
})
