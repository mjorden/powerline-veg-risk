# Synthetic corridor (as in test-risk.R): E-W line along y = 0 on the UTM 13N
# central meridian (no grid convergence), conductor 10 m above flat ground.
utm <- sf::st_crs(26913)
x0 <- 500000
y0 <- 4400000

make_rasters <- function(trees) {
  r <- terra::rast(xmin = x0, xmax = x0 + 200, ymin = y0 - 50, ymax = y0 + 50,
                   resolution = 1, crs = "EPSG:26913")
  xy <- terra::crds(r, na.rm = FALSE)
  h <- numeric(nrow(xy))
  for (i in seq_len(nrow(trees))) {
    d <- sqrt((xy[, 1] - trees$x[i])^2 + (xy[, 2] - trees$y[i])^2)
    h <- pmax(h, trees$h[i] - 2 * d)
  }
  list(dtm = terra::setValues(r, 0), chm = terra::setValues(r, ifelse(h > 0, h, NA)))
}

screen <- function(trees) {
  r <- make_rasters(trees)
  ln <- sf::st_sf(geometry = sf::st_sfc(sf::st_linestring(rbind(c(x0, y0), c(x0 + 200, y0))), crs = utm))
  s <- segment_lines(ln, utm, seg_m = 100)
  no_wires <- data.table::data.table(X = numeric(), Y = numeric(), height_m = numeric(),
                                     pred = factor(character(), levels = label_levels))
  prof <- conductor_profile(no_wires, s, r$dtm, min_ground_clear_m = 10, attach_m = 10)
  list(profile = prof, risk = assess_risk(r, prof, s, phase_offset_m = 3, tree_ws_m = 3))
}

# One 15 m strike tree 13.5 m north of the line in segment 1, one 13.5 m
# south in segment 2.
two_trees <- function() screen(data.frame(x = x0 + c(50.5, 150.5), y = y0 + c(13.5, -13.5), h = 15))

winds <- function(dir_from, gust = 20, rh = 15) {
  out <- tibble::tibble(time = as.POSIXct("2021-12-30 18:00", tz = "UTC") + 3600 * seq_along(dir_from),
                        wind_ms = gust / 2, gust_ms = gust, dir_from_deg = dir_from, rh_pct = rh)
  fire_wind_hours(out, min_gust_ms = 0, max_rh = Inf)
}

test_that("the hitting arc follows from the 3D reach", {
  sc <- two_trees()
  rk <- wind_fall_exposure(sc$risk, sc$profile, winds(0), min_hours = 1)
  tt <- rk$trees[order(rk$trees$seg_id), ]
  # d = 13.5 - 3 = 10.5, dz = 10, h = 15: R^2 = 225 - 100 = 125
  expect_equal(tt$arc_lo_deg, rep(acos(10.5 / sqrt(125)) * 180 / pi, 2), tolerance = 0.5)
  expect_equal(tt$bearing_deg, c(180, 0), tolerance = 1)
})

test_that("a north wind throws the north tree into the line, not the south one", {
  sc <- two_trees()
  rk <- wind_fall_exposure(sc$risk, sc$profile, winds(rep(0, 10)), min_hours = 1)
  tt <- rk$trees[order(rk$trees$seg_id), ]
  expect_equal(tt$wind_hit_lo, c(1, 0))
  s <- sf::st_drop_geometry(rk$segments)
  s <- s[order(s$seg_id), ]
  expect_equal(s$wind_strike_lo, c(1, 0))
  expect_equal(s$n_strike_windward_lo, c(1L, 0L))
  expect_equal(attr(rk$segments, "wind")$n_hours, 10)
})

test_that("an oblique wind hits only within the arc plus spread", {
  sc <- two_trees()
  # Wind towards 240 (from 60): 60 degrees off the north tree's bearing of 180.
  narrow <- wind_fall_exposure(sc$risk, sc$profile, winds(60), spread_deg = 15, min_hours = 1)
  wide <- wind_fall_exposure(sc$risk, sc$profile, winds(60), spread_deg = 45, min_hours = 1)
  north <- function(rk) rk$trees$wind_hit_lo[rk$trees$seg_id == 1]
  expect_equal(north(narrow), 0)
  expect_equal(north(wide), 1)
  # Half the hours from the north, half from the south: each tree hit half the time.
  mixed <- wind_fall_exposure(sc$risk, sc$profile, winds(c(0, 180)), min_hours = 1)
  expect_equal(mixed$trees$wind_hit_lo, c(0.5, 0.5))
})

test_that("fire-weather hours combine a gust quantile with a humidity cap", {
  w <- tibble::tibble(time = as.POSIXct("2020-01-01", tz = "UTC") + 3600 * 0:99,
                      wind_ms = 1, gust_ms = 1:100, dir_from_deg = 270, rh_pct = rep(c(10, 50), 50))
  f <- fire_wind_hours(w, gust_quantile = 0.9, max_rh = 30)
  expect_equal(attr(f, "min_gust_ms"), stats::quantile(1:100, 0.9, names = FALSE))
  expect_true(all(f$gust_ms >= 90.1 & f$rh_pct <= 30))
  expect_equal(nrow(f), 5)
  expect_equal(attr(f, "n_record"), 100)
})

test_that("grid convergence is zero on the central meridian and negative east of it", {
  on_cm <- sf::st_sfc(sf::st_point(c(500000, 4428000)), crs = 26913)
  east <- sf::st_transform(sf::st_sfc(sf::st_point(c(-102, 40)), crs = 4326), 26913)
  expect_equal(grid_convergence(on_cm), 0, tolerance = 0.01)
  expect_equal(grid_convergence(east), -3 * sin(40 * pi / 180), tolerance = 0.05)
})

test_that("Open-Meteo and NWS responses parse", {
  om <- list(latitude = 40.035, longitude = -105.357,
             hourly = list(time = c("2021-12-30T18:00", "2021-12-30T19:00"),
                           wind_speed_10m = c(20, 22), wind_gusts_10m = c(35, NA),
                           wind_direction_10m = c(275, 280), relative_humidity_2m = c(12, 11)))
  w <- parse_openmeteo(om)
  expect_equal(w$gust_ms, c(35, NA))
  expect_equal(format(w$time[2], "%H"), "19")
  expect_equal(attr(w, "lat"), 40.035)

  expect_equal(iso_hours("PT4H"), 4)
  expect_equal(iso_hours("P1DT6H"), 30)
  expect_equal(iso_hours("P1D"), 24)
  props <- list(
    windGust = list(uom = "wmoUnit:km_h-1", values = list(
      list(validTime = "2026-10-19T12:00:00+00:00/PT2H", value = 72),
      list(validTime = "2026-10-19T14:00:00+00:00/PT1H", value = 36))),
    windSpeed = list(uom = "wmoUnit:km_h-1", values = list(
      list(validTime = "2026-10-19T12:00:00+00:00/PT3H", value = 36))),
    windDirection = list(values = list(list(validTime = "2026-10-19T12:00:00+00:00/PT3H", value = 270))),
    relativeHumidity = list(values = list(list(validTime = "2026-10-19T12:00:00+00:00/PT3H", value = 14)))
  )
  g <- parse_nws_grid(props)
  expect_equal(nrow(g), 3)
  expect_equal(g$gust_ms, c(20, 20, 10))
  expect_equal(g$wind_ms, rep(10, 3))
  expect_equal(g$dir_from_deg, rep(270, 3))

  a <- parse_nws_alerts(list(list(properties = list(
    event = "Red Flag Warning", onset = "2026-10-19T12:00:00-06:00", ends = "2026-10-20T00:00:00-06:00",
    headline = "Red Flag Warning issued"))))
  expect_equal(a$event, "Red Flag Warning")
  expect_equal(format(a$onset, "%Y-%m-%d %H:%M", tz = "UTC"), "2026-10-19 18:00")
  expect_equal(nrow(parse_nws_alerts(list())), 0)
})

test_that("the watchlist flags segments whose strike trees the forecast wind would throw", {
  sc <- two_trees()
  rk <- wind_fall_exposure(sc$risk, sc$profile, fire_wind_hours(
    tibble::tibble(time = Sys.time(), wind_ms = 5, gust_ms = 20, dir_from_deg = 0, rh_pct = 10),
    min_gust_ms = 15, max_rh = 30), min_hours = 1)
  t0 <- as.POSIXct("2026-10-20 06:00", tz = "UTC")
  fc <- tibble::tibble(time = t0 + 3600 * 0:3, wind_ms = 8,
                       gust_ms = c(10, 22, 25, 22), dir_from_deg = c(0, 0, 0, 180), rh_pct = c(10, 12, 50, 12))
  wl <- forecast_watchlist(rk, fc, now = t0)
  # Hour 1 too calm, hour 3 too humid; hour 2 (north wind) hits segment 1,
  # hour 4 (south wind) hits segment 2.
  expect_equal(nrow(attr(wl, "hours")), 2)
  expect_equal(attr(wl, "settings")$bound, "lo")
  expect_equal(attr(wl, "settings")$n_past_hours_dropped, 0)
  expect_setequal(wl$seg_id, c(1, 2))
  expect_equal(wl$first_hour[wl$seg_id == 1], t0 + 3600)
  expect_equal(wl$first_hour[wl$seg_id == 2], t0 + 3 * 3600)
  expect_true(all(wl$n_trees_exposed == 1))
  expect_false(any(wl$red_flag))

  # A Red Flag Warning flags the humid hour too.
  rf <- tibble::tibble(event = "Red Flag Warning", onset = t0 + 2 * 3600, ends = t0 + 2 * 3600,
                       headline = "")
  wl2 <- forecast_watchlist(rk, fc, alerts = rf, now = t0)
  expect_equal(nrow(attr(wl2, "hours")), 3)
  expect_true(wl2$red_flag[wl2$seg_id == 1])

  calm <- forecast_watchlist(rk, transform(fc, gust_ms = 1), now = t0)
  expect_equal(nrow(calm), 0)
  expect_equal(attr(calm, "settings")$min_gust_ms, 15)
})

watchlist_fixture <- function() {
  sc <- two_trees()
  rk <- wind_fall_exposure(sc$risk, sc$profile, fire_wind_hours(
    tibble::tibble(time = Sys.time(), wind_ms = 5, gust_ms = 20, dir_from_deg = 0, rh_pct = 10),
    min_gust_ms = 15, max_rh = 30), min_hours = 1)
  t0 <- as.POSIXct("2026-10-20 06:00", tz = "UTC")
  fc <- tibble::tibble(time = t0 + 3600 * 0:3, wind_ms = 8,
                       gust_ms = c(10, 22, 25, 22), dir_from_deg = c(0, 0, 0, 180), rh_pct = c(10, 12, 50, 12))
  list(rk = rk, t0 = t0, fc = fc)
}

test_that("forecast hours already past are not flagged as coming weather (#29)", {
  f <- watchlist_fixture()
  # 08:30: hours 06:00 and 07:00 are gone; 08:00 (humid) and 09:00 (south wind) remain.
  wl <- forecast_watchlist(f$rk, f$fc, now = f$t0 + 2.5 * 3600)
  expect_equal(attr(wl, "settings")$n_past_hours_dropped, 2)
  expect_equal(wl$seg_id, 2)
  expect_equal(wl$first_hour, f$t0 + 3 * 3600)
  # The hour in progress is kept.
  wl_now <- forecast_watchlist(f$rk, f$fc, now = f$t0 + 3600 + 1800)
  expect_setequal(wl_now$seg_id, c(1, 2))
})

test_that("red-flag hours with no gust or humidity give NA, not +/-Inf (#29)", {
  f <- watchlist_fixture()
  fc <- f$fc
  fc$gust_ms <- NA_real_
  fc$rh_pct <- NA_real_
  rf <- tibble::tibble(event = "Red Flag Warning", onset = f$t0, ends = f$t0 + 4 * 3600, headline = "")
  expect_silent(wl <- forecast_watchlist(f$rk, fc, alerts = rf, now = f$t0))
  expect_equal(nrow(attr(wl, "hours")), 4)
  expect_true(all(is.na(wl$max_gust_ms)))
  expect_true(all(is.na(wl$min_rh_pct)))
  expect_true(all(wl$red_flag))
})

test_that("an undefined gust threshold is refused, not propagated (#29, #14)", {
  all_na <- tibble::tibble(time = as.POSIXct("2020-01-01", tz = "UTC") + 3600 * 0:9,
                           wind_ms = 1, gust_ms = NA_real_, dir_from_deg = 270, rh_pct = 10)
  expect_error(fire_wind_hours(all_na), "undefined")
  f <- watchlist_fixture()
  expect_error(forecast_watchlist(f$rk, f$fc, min_gust_ms = NA_real_, now = f$t0), "min_gust_ms")
  expect_error(forecast_watchlist(f$rk, f$fc, max_rh = NA, now = f$t0), "max_rh")
  # A risk object without hitting arcs is caught before the vapply.
  sc <- two_trees()
  expect_error(forecast_watchlist(sc$risk, f$fc, min_gust_ms = 15, now = f$t0), "wind_fall_exposure")
})

test_that("no fire-weather hours gives NA exposure, not zero, and the count survives (#14)", {
  sc <- two_trees()
  none <- fire_wind_hours(tibble::tibble(time = Sys.time(), wind_ms = 1, gust_ms = 2,
                                         dir_from_deg = 0, rh_pct = 90), min_gust_ms = 15, max_rh = 30)
  expect_equal(nrow(none), 0)
  expect_warning(rk <- wind_fall_exposure(sc$risk, sc$profile, none), "No fire-weather hours")
  s <- sf::st_drop_geometry(rk$segments)
  expect_true(all(is.na(s$wind_strike_lo)))
  expect_true(all(is.na(s$n_strike_windward_hi)))
  expect_equal(s$n_fire_weather_hours, c(0L, 0L))
  expect_true(all(is.na(rk$trees$wind_hit_lo)))
  few <- fire_wind_hours(tibble::tibble(time = Sys.time() + 3600 * 1:5, wind_ms = 5, gust_ms = 20,
                                        dir_from_deg = 0, rh_pct = 10), min_gust_ms = 15, max_rh = 30)
  expect_warning(rk2 <- wind_fall_exposure(sc$risk, sc$profile, few, min_hours = 24), "Only 5")
  expect_equal(unique(sf::st_drop_geometry(rk2$segments)$n_fire_weather_hours), 5L)
})
