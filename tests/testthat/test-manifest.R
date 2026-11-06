test_that("run_environment() and git_state() record what a run depends on", {
  env <- run_environment()
  expect_true(all(c("r_version", "platform", "packages", "sf_ext", "threads", "rng_kind") %in% names(env)))
  expect_true("sf" %in% names(env$packages))
  expect_true(all(c("GDAL", "GEOS", "PROJ") %in% names(env$sf_ext)))
  g <- git_state(tempdir())
  expect_true(is.na(g$sha) || is.character(g$sha))
})

test_that("file_record() and defaults_of() describe files and resolved defaults", {
  f <- tempfile(fileext = ".csv")
  d <- data.frame(a = 1:3, b = c("x", "y", "z"))
  write.csv(d, f, row.names = FALSE)
  rec <- file_record(f, d)
  expect_equal(rec$md5, unname(tools::md5sum(f)))
  expect_equal(rec$rows, 3)
  expect_equal(vapply(rec$columns, `[[`, "", "name"), c("a", "b"))
  dflt <- defaults_of(assess_risk)
  expect_equal(dflt$under_line_m, 8)
  expect_equal(dflt$clearance_target_m, 4.6)
  expect_null(defaults_of(assess_risk, c("rasters", "under_line_m"))$rasters)
})

test_that("write_manifest() is atomic and read_run() refuses incomplete or mismatched runs (#54)", {
  site <- file.path(tempfile("site"), "out")
  run_id <- "20261023T120000Z-abc1234"
  run_dir <- file.path(site, "runs", run_id)
  dir.create(run_dir, recursive = TRUE)
  expect_error(read_run(site), "latest.txt")
  writeLines(run_id, file.path(site, "latest.txt"))
  expect_error(read_run(site), "no manifest")
  seg <- sf::st_sf(seg_id = 1:2, run_id = run_id,
                   geometry = sf::st_sfc(sf::st_point(c(0, 0)), sf::st_point(c(1, 1)), crs = 26913))
  sf::st_write(seg, file.path(run_dir, "segments.gpkg"), quiet = TRUE)
  write_manifest(list(schema_version = 1L, run_id = run_id, status = "failed", error = "boom"), run_dir)
  expect_false(file.exists(file.path(run_dir, "manifest.json.tmp")))
  expect_error(read_run(site), "not complete")
  write_manifest(list(schema_version = 1L, run_id = run_id, status = "complete", started_utc = Sys.time()), run_dir)
  r <- read_run(site)
  expect_equal(r$run_id, run_id)
  expect_equal(r$manifest$status, "complete")
  # A table from another run is refused.
  seg$run_id <- "other"
  sf::st_write(seg, file.path(run_dir, "trees.gpkg"), quiet = TRUE)
  expect_error(read_run(site), "carries run id other")
  expect_equal(read_run(site, check = "segments.gpkg")$run_id, run_id)
})
