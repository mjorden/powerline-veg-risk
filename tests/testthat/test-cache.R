csv_cache <- function(dir, args, fetch, ...) {
  cache_get("thing", args, dir = dir, ext = "csv", fetch = fetch,
            read = function(path, meta) utils::read.csv(path),
            write = function(x, path) utils::write.csv(x, path, row.names = FALSE), ...)
}

test_that("cache_key() depends on the request, not on argument order or integer/double (#56)", {
  a <- cache_key("osm_line", list(ids = "1", date = "2026-10-19T14:01:07Z"))
  b <- cache_key("osm_line", list(date = "2026-10-19T14:01:07Z", ids = "1"))
  expect_equal(a$key, b$key)
  expect_match(a$key, "^[0-9a-f]{16}$")
  expect_equal(cache_key("k", list(n = 1L))$key, cache_key("k", list(n = 1))$key)
  expect_false(cache_key("osm_line", list(ids = "2"))$key == a$key)
  expect_false(cache_key("osm_structures", list(ids = "1"))$key == cache_key("osm_line", list(ids = "1"))$key)
  expect_false(cache_key("k", list(ids = "1"), upstream = list(tiles = "abc"))$key == cache_key("k", list(ids = "1"))$key)
  expect_error(cache_key("bad kind", list(a = 1)), "one word")
  expect_error(cache_key("k", list(1, 2)), "named")
})

test_that("cache_get() fetches once, writes atomically with a sidecar, and reuses a valid entry (#56)", {
  dir <- tempfile("cache")
  n <- 0
  fetch <- function() { n <<- n + 1; data.frame(a = 1:3, b = c("x", "y", "z")) }
  x <- csv_cache(dir, list(ids = "1"), fetch)
  expect_equal(n, 1)
  expect_false(attr(x, "cache")$hit)
  path <- attr(x, "cache")$path
  expect_true(file.exists(path))
  expect_true(file.exists(paste0(path, ".meta.json")))
  expect_length(list.files(dir, pattern = "\\.tmp$"), 0)
  meta <- jsonlite::read_json(paste0(path, ".meta.json"))
  expect_equal(meta$kind, "thing")
  expect_equal(meta$args$ids, "1")
  expect_equal(meta$file$md5, unname(tools::md5sum(path)))
  expect_equal(meta$n, 3)
  y <- csv_cache(dir, list(ids = "1"), fetch)
  expect_equal(n, 1)                        # served from the cache
  expect_true(attr(y, "cache")$hit)
  expect_equal(y$b, c("x", "y", "z"))
  # A different request is a different entry.
  z <- csv_cache(dir, list(ids = "2"), fetch)
  expect_equal(n, 2)
  expect_false(attr(z, "cache")$path == path)
  expect_length(list.files(dir, pattern = "\\.csv$"), 2)
})

test_that("cache_get() refuses an entry without a sidecar, with another request, or with a changed file (#56)", {
  dir <- tempfile("cache")
  n <- 0
  fetch <- function() { n <<- n + 1; data.frame(a = n) }
  x <- csv_cache(dir, list(ids = "1"), fetch)
  path <- attr(x, "cache")$path
  meta_path <- paste0(path, ".meta.json")
  # The file was edited after it was cached.
  writeLines(c("a", "99"), path)
  expect_message(y <- csv_cache(dir, list(ids = "1"), fetch), "checksum")
  expect_equal(n, 2)
  expect_equal(y$a, 2)
  expect_equal(jsonlite::read_json(meta_path)$file$md5, unname(tools::md5sum(path)))
  # No sidecar: a file by name alone proves nothing.
  unlink(meta_path)
  expect_message(csv_cache(dir, list(ids = "1"), fetch), "no sidecar")
  expect_equal(n, 3)
  # A sidecar that records another request.
  m <- jsonlite::read_json(meta_path)
  m$request <- "other"
  jsonlite::write_json(m, meta_path, auto_unbox = TRUE)
  expect_message(csv_cache(dir, list(ids = "1"), fetch), "different request")
  expect_equal(n, 4)
  # Valid again.
  csv_cache(dir, list(ids = "1"), fetch)
  expect_equal(n, 4)
})

test_that("cache_get() honours the refresh policy and a fetch that asks not to be cached (#56)", {
  dir <- tempfile("cache")
  n <- 0
  fetch <- function() { n <<- n + 1; data.frame(a = n) }
  expect_error(csv_cache(dir, list(ids = "1"), fetch, refresh = "never"), "never")
  expect_equal(n, 0)
  csv_cache(dir, list(ids = "1"), fetch)
  x <- csv_cache(dir, list(ids = "1"), fetch, refresh = "always")
  expect_equal(n, 2)
  expect_equal(x$a, 2)
  expect_equal(csv_cache(dir, list(ids = "1"), fetch, refresh = "never")$a, 2)
  # The fetch flags a result that must not be cached.
  skip_fetch <- function() { n <<- n + 1; structure(data.frame(a = n), cache_skip = "incomplete") }
  y <- csv_cache(dir, list(ids = "3"), skip_fetch)
  expect_false(attr(y, "cache")$cached)
  expect_equal(attr(y, "cache")$skipped, "incomplete")
  expect_null(attr(y, "cache_skip"))
  expect_length(list.files(dir, pattern = "\\.csv$"), 1)
  z <- csv_cache(dir, list(ids = "3"), skip_fetch)
  expect_equal(z$a, 4)                      # fetched again, nothing on disk
  withr::with_envvar(c(VEGRISK_REFRESH = "osm_line, wind_hourly", VEGRISK_OFFLINE = ""), {
    expect_equal(cache_policy("osm_line"), "always")
    expect_equal(cache_policy("osm_buildings"), "missing")
  })
  withr::with_envvar(c(VEGRISK_REFRESH = "all"), expect_equal(cache_policy("x"), "always"))
  withr::with_envvar(c(VEGRISK_OFFLINE = "1"), expect_equal(cache_policy("x"), "never"))
})

test_that("cache_get() records what the fetch reports and hands it back on read (#56)", {
  dir <- tempfile("cache")
  fetch <- function() structure(data.frame(a = 1), stamp = "2026-10-19T14:01:07Z")
  read <- function(path, meta) structure(utils::read.csv(path), stamp = meta$source$stamp)
  write <- function(x, path) utils::write.csv(x, path, row.names = FALSE)
  extra <- function(x) list(stamp = attr(x, "stamp"))
  cache_get("t", list(a = 1), dir, fetch, read, write, "csv", extra = extra)
  x <- cache_get("t", list(a = 1), dir, function() stop("no"), read, write, "csv", extra = extra)
  expect_equal(attr(x, "stamp"), "2026-10-19T14:01:07Z")
  expect_equal(attr(x, "cache")$meta$source$stamp, "2026-10-19T14:01:07Z")
})

test_that("training_fingerprint() names what changed between two fits (#56)", {
  feat <- data.frame(X = c(1, 2, 3), Y = c(1, 1, 1), Z = c(5, 6, 7), label = factor(c("vegetation", "wire", "building")))
  f <- training_fingerprint(feat, params = list(wire_search_m = 12), tiles = c("aaa", "bbb"))
  expect_true(fingerprint_diff(f, training_fingerprint(feat[3:1, ], params = list(wire_search_m = 12), tiles = c("bbb", "aaa"))))
  expect_equal(f$n_points, 3)
  g <- training_fingerprint(transform(feat, label = factor(c("vegetation", "vegetation", "building"))),
                            params = list(wire_search_m = 12), tiles = c("aaa", "bbb"))
  expect_equal(fingerprint_diff(f, g), "points")
  h <- training_fingerprint(feat, params = list(wire_search_m = 20), tiles = c("aaa"))
  expect_equal(fingerprint_diff(f, h), c("params", "tiles"))
  expect_match(fingerprint_diff(NULL, f), "predates")
  expect_error(training_fingerprint(feat[, c("X", "Y")]), "needs columns")
})
