# Fire-weather wind: which strike trees the dangerous winds would throw
# into the line (historical reanalysis via Open-Meteo), and which segments to
# watch in the coming days (National Weather Service forecast and alerts).
#
# Weather grids are kilometres wide, so a short corridor gets one wind record
# for every segment. The spatial signal comes from combining wind *direction*
# with each tree's position relative to the line: windthrown trees fall
# downwind, so a strike tree on the upwind side of the line during dry,
# high-wind hours matters more than the same tree on the downwind side.

openmeteo_archive <- "https://archive-api.open-meteo.com/v1/archive"
nws_api <- "https://api.weather.gov"
vegrisk_ua <- "vegrisk R package (github.com/mjorden/powerline-veg-risk)"

#' Hourly historical wind and humidity for a corridor
#'
#' Fetches hourly 10 m wind speed, gusts and direction and 2 m relative
#' humidity from the Open-Meteo historical archive (ERA5 reanalysis, roughly
#' 10-25 km grid; free, no key, CC BY 4.0) at the centroid of `aoi`.
#'
#' Reanalysis winds describe the regional flow. They don't resolve terrain
#' channelling in a canyon or gusts at a ridge crest.
#'
#' @param aoi An `sf`/`sfc` object (any CRS) or a `bbox`.
#' @param start_date,end_date Dates (or `"YYYY-MM-DD"` strings).
#' @param url Archive endpoint.
#' @return A tibble: `time` (UTC), `wind_ms`, `gust_ms`, `dir_from_deg`
#'   (direction the wind blows *from*, degrees clockwise from true north) and
#'   `rh_pct`. Attributes `lon`, `lat` give the grid cell used.
#' @export
wind_history <- function(aoi, start_date, end_date, url = openmeteo_archive) {
  ll <- aoi_lonlat(aoi)
  q <- sprintf(paste0("%s?latitude=%.5f&longitude=%.5f&start_date=%s&end_date=%s",
                      "&hourly=wind_speed_10m,wind_gusts_10m,wind_direction_10m,relative_humidity_2m",
                      "&wind_speed_unit=ms&timezone=UTC"),
               url, ll[2], ll[1], as.Date(start_date), as.Date(end_date))
  resp <- httr2::request(q) |>
    httr2::req_user_agent(vegrisk_ua) |>
    httr2::req_retry(max_tries = 4) |>
    httr2::req_perform() |>
    httr2::resp_body_json(simplifyVector = TRUE)
  parse_openmeteo(resp)
}

parse_openmeteo <- function(resp) {
  h <- resp$hourly
  num <- function(x) as.numeric(unlist(lapply(x, function(v) if (is.null(v)) NA else v)))
  out <- tibble::tibble(
    time         = as.POSIXct(unlist(h$time), format = "%Y-%m-%dT%H:%M", tz = "UTC"),
    wind_ms      = num(h$wind_speed_10m),
    gust_ms      = num(h$wind_gusts_10m),
    dir_from_deg = num(h$wind_direction_10m),
    rh_pct       = num(h$relative_humidity_2m)
  )
  attr(out, "lon") <- resp$longitude
  attr(out, "lat") <- resp$latitude
  out
}

#' Select dry, high-wind ("fire-weather") hours
#'
#' Keeps hours with gusts at or above `min_gust_ms` (default: the
#' `gust_quantile` of the whole record) and relative humidity at or below
#' `max_rh`. These are the conditions under which a tree blown into the line
#' can start a fire that spreads.
#'
#' @param wind Output of [wind_history()] or [nws_forecast()].
#' @param gust_quantile Quantile of the record used as the gust threshold
#'   when `min_gust_ms` is `NULL`.
#' @param min_gust_ms Absolute gust threshold (m/s); overrides the quantile.
#' @param max_rh Maximum relative humidity (percent); `Inf` keeps all.
#' @return The selected rows, with attributes `min_gust_ms`, `max_rh` and
#'   `n_record` (hours in the full record).
#' @export
fire_wind_hours <- function(wind, gust_quantile = 0.95, min_gust_ms = NULL, max_rh = 30) {
  if (is.null(min_gust_ms)) {
    min_gust_ms <- stats::quantile(wind$gust_ms, gust_quantile, na.rm = TRUE, names = FALSE)
  }
  if (length(min_gust_ms) != 1 || !is.finite(min_gust_ms)) {
    rlang::abort(paste("The gust threshold is undefined: `min_gust_ms` is not a finite number",
                       "(an all-NA `gust_ms` record gives an NA quantile)."))
  }
  sel <- !is.na(wind$gust_ms) & !is.na(wind$dir_from_deg) & wind$gust_ms >= min_gust_ms &
    (is.infinite(max_rh) | (!is.na(wind$rh_pct) & wind$rh_pct <= max_rh))
  out <- wind[sel, ]
  attr(out, "min_gust_ms") <- min_gust_ms
  attr(out, "max_rh") <- max_rh
  attr(out, "n_record") <- nrow(wind)
  out
}

#' Which strike trees the fire-weather winds would throw into the line
#'
#' For each potential strike tree from [assess_risk()], works out the arc of
#' fall directions that reach a conductor, then the share of fire-weather
#' hours whose wind would push the tree into that arc.
#'
#' A tree of height `h` whose base is a horizontal distance `d` from the
#' outer phase, with the conductor `dz` above its base, reaches the conductor
#' horizontally out to `R = sqrt(h^2 - dz^2)`. It hits if it falls within
#' `acos(d / R)` of the direction straight at the line, the same 3D test as
#' the fall-in screen, resolved by direction. Windthrown trees fall roughly
#' downwind, so a fire-weather hour counts against the tree when the
#' direction the wind blows *towards* lies inside that arc, widened by
#' `spread_deg` on each side for the scatter of real fall directions.
#'
#' Wind directions are rotated from true north to grid north (meridian
#' convergence at the corridor) before they are compared with tree bearings.
#'
#' @param risk Output of [assess_risk()].
#' @param profile Output of [conductor_profile()] (line geometry).
#' @param wind_hours Output of [fire_wind_hours()].
#' @param phase_offset_m,growth_m As used in [assess_risk()].
#' @param spread_deg Allowance (degrees, each side) for fall directions that
#'   deviate from the wind direction.
#' @param windward_min Share of fire-weather hours at or above which a strike
#'   tree counts as *windward* of the line.
#' @param min_hours Fewer fire-weather hours than this gives a warning: the
#'   hit shares then rest on a handful of hours. With none at all, every
#'   wind column is `NA`, not zero.
#' @return `risk` with added tree columns `bearing_deg` (grid bearing from
#'   the tree to the line), `arc_lo_deg`, `arc_hi_deg` (half-width of the
#'   hitting arc under each conductor bound; `NA` when it cannot reach),
#'   `wind_hit_lo`, `wind_hit_hi` (share of fire-weather hours that would
#'   throw it into the line), and segment columns `wind_strike_lo`,
#'   `wind_strike_hi` (sum of `wind_hit_*` over strike trees: the expected
#'   number thrown towards the line in a fire-weather hour),
#'   `n_strike_windward_lo`, `n_strike_windward_hi` and
#'   `n_fire_weather_hours` (so the hour count survives `st_write()`). The
#'   fire-wind summary is stored in `attr(risk$segments, "wind")`.
#' @export
wind_fall_exposure <- function(risk, profile, wind_hours, phase_offset_m = 3, growth_m = 0,
                               spread_deg = 15, windward_min = 0.5, min_hours = 24) {
  trees <- risk$trees
  crs <- sf::st_crs(trees)
  m <- crs_m_per_unit(crs)
  conv <- grid_convergence(sf::st_as_sfc(sf::st_bbox(risk$segments)))
  wind_to <- (wind_hours$dir_from_deg + 180 + conv) %% 360
  n_hours <- nrow(wind_hours)
  if (n_hours == 0) {
    rlang::warn("No fire-weather hours: every wind exposure column is NA.")
  } else if (n_hours < min_hours) {
    rlang::warn(sprintf("Only %d fire-weather hours (min_hours = %d): hit shares rest on very few hours.",
                        n_hours, min_hours))
  }

  trees <- fall_geometry(trees, profile, m, phase_offset_m, growth_m)
  hit <- function(arc) {
    if (length(wind_to) == 0) return(rep(NA_real_, nrow(trees)))
    vapply(seq_len(nrow(trees)), function(i) {
      if (is.na(arc[i])) return(0)
      mean(ang_diff(wind_to, trees$bearing_deg[i]) <= arc[i] + spread_deg)
    }, 0)
  }
  trees$wind_hit_lo <- hit(trees$arc_lo_deg)
  trees$wind_hit_hi <- hit(trees$arc_hi_deg)

  seg <- risk$segments
  # With no hours the hit shares are NA, and so are the segment sums: zero
  # would read as "no windward trees".
  per_seg <- function(col, strike) vapply(seg$seg_id, function(s) {
    if (n_hours == 0) return(NA_real_)
    sel <- trees$seg_id == s & trees[[strike]]
    sum(trees[[col]][sel], na.rm = TRUE)
  }, 0)
  count_seg <- function(col, strike) vapply(seg$seg_id, function(s) {
    if (n_hours == 0) return(NA_integer_)
    sum(trees$seg_id == s & trees[[strike]] & trees[[col]] >= windward_min, na.rm = TRUE)
  }, 0L)
  seg$wind_strike_lo <- per_seg("wind_hit_lo", "strike_lo")
  seg$wind_strike_hi <- per_seg("wind_hit_hi", "strike_hi")
  seg$n_strike_windward_lo <- count_seg("wind_hit_lo", "strike_lo")
  seg$n_strike_windward_hi <- count_seg("wind_hit_hi", "strike_hi")
  seg$n_fire_weather_hours <- n_hours

  attr(seg, "wind") <- list(n_hours = n_hours, n_record = attr(wind_hours, "n_record"),
                            min_gust_ms = attr(wind_hours, "min_gust_ms"),
                            max_rh = attr(wind_hours, "max_rh"),
                            dir_from_deg = wind_hours$dir_from_deg,
                            convergence_deg = conv, spread_deg = spread_deg,
                            windward_min = windward_min,
                            lon = attr(wind_hours, "lon"), lat = attr(wind_hours, "lat"))
  # Per-segment attributes survive in the list; keep the dryness ones too.
  for (a in setdiff(names(attributes(risk$segments)), names(attributes(seg)))) {
    attr(seg, a) <- attr(risk$segments, a)
  }
  risk$segments <- seg
  risk$trees <- trees
  risk
}

# Bearing from each tree to the nearest line point, and the half-width of
# the arc of fall directions that reaches the conductor under each bound.
fall_geometry <- function(trees, profile, m, phase_offset_m, growth_m) {
  if (nrow(trees) == 0) {
    for (k in c("bearing_deg", "arc_lo_deg", "arc_hi_deg")) trees[[k]] <- numeric()
    return(trees)
  }
  xy <- sf::st_coordinates(trees)[, 1:2, drop = FALSE]
  # Straight at the line: along the local normal, towards the centreline.
  p <- line_project(xy, profile, m)
  nx <- -profile$ty[p$vertex]
  ny <- profile$tx[p$vertex]
  trees$bearing_deg <- (atan2(-p$offset_m * nx, -p$offset_m * ny) * 180 / pi) %% 360
  d <- pmax(trees$dh_m - phase_offset_m, 0)
  h <- trees$height_m + growth_m
  arc <- function(reach) {
    # reach^2 = d^2 + dz^2, so the horizontal reach at conductor height is
    # R^2 = h^2 - dz^2 = h^2 - reach^2 + d^2.
    r2 <- h^2 - reach^2 + d^2
    ifelse(is.finite(reach) & h >= reach & r2 > 0, acos(pmin(d / sqrt(pmax(r2, 0)), 1)) * 180 / pi, NA_real_)
  }
  trees$arc_lo_deg <- arc(trees$reach_lo_m)
  trees$arc_hi_deg <- arc(trees$reach_hi_m)
  trees
}

# Smallest angle between two bearings (degrees, 0-180).
ang_diff <- function(a, b) abs(((a - b + 180) %% 360) - 180)

# Grid bearing (degrees, clockwise from grid north) of true north at the
# centre of `g`: add it to a true bearing to get a grid bearing.
grid_convergence <- function(g) {
  crs <- sf::st_crs(g)
  ll <- aoi_lonlat(g)
  p <- sf::st_transform(sf::st_sfc(sf::st_point(ll), sf::st_point(ll + c(0, 0.01)), crs = 4326), crs)
  xy <- sf::st_coordinates(p)
  unname(atan2(xy[2, 1] - xy[1, 1], xy[2, 2] - xy[1, 2]) * 180 / pi)
}

aoi_lonlat <- function(aoi) {
  bb <- sf::st_bbox(sf::st_transform(sf::st_as_sfc(sf::st_bbox(aoi)), 4326))
  c(mean(bb[c("xmin", "xmax")]), mean(bb[c("ymin", "ymax")]))
}

#' Hourly National Weather Service forecast for a corridor
#'
#' Looks up the NWS forecast grid cell (2.5 km) at the centroid of `aoi` and
#' returns its hourly wind, gust, direction and humidity for the next ~7
#' days. United States only; free, no key.
#'
#' @param aoi An `sf`/`sfc` object (any CRS) or a `bbox`.
#' @param api NWS API root.
#' @return A tibble with the same columns as [wind_history()]; attributes
#'   `office`, `grid` and `updated`.
#' @export
nws_forecast <- function(aoi, api = nws_api) {
  ll <- aoi_lonlat(aoi)
  pt <- nws_get(sprintf("%s/points/%.4f,%.4f", api, ll[2], ll[1]))
  grid <- nws_get(pt$properties$forecastGridData)
  out <- parse_nws_grid(grid$properties)
  attr(out, "office") <- pt$properties$gridId
  attr(out, "grid") <- paste(pt$properties$gridX, pt$properties$gridY, sep = ",")
  out
}

#' Active NWS watches, warnings and advisories at a corridor
#'
#' @inheritParams nws_forecast
#' @return A tibble: `event` (e.g. `"Red Flag Warning"`), `onset`, `ends`,
#'   `headline`. Zero rows when nothing is active.
#' @export
nws_alerts <- function(aoi, api = nws_api) {
  ll <- aoi_lonlat(aoi)
  resp <- nws_get(sprintf("%s/alerts/active?point=%.4f,%.4f", api, ll[2], ll[1]))
  parse_nws_alerts(resp$features)
}

nws_get <- function(url) {
  httr2::request(url) |>
    httr2::req_user_agent(vegrisk_ua) |>
    httr2::req_headers(Accept = "application/geo+json") |>
    httr2::req_retry(max_tries = 4) |>
    httr2::req_perform() |>
    httr2::resp_body_json()
}

parse_nws_alerts <- function(features) {
  p <- lapply(features, `[[`, "properties")
  get <- function(k) vapply(p, function(x) x[[k]] %||% NA_character_, "")
  tm <- function(x) as.POSIXct(sub("([+-]\\d\\d):(\\d\\d)$", "\\1\\2", x), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
  tibble::tibble(event = get("event"), onset = tm(get("onset")), ends = tm(get("ends")),
                 headline = get("headline"))
}

# NWS grid layers are run-length encoded: "2026-10-19T12:00:00+00:00/PT4H".
# Expand each to hourly values and join the layers on the hour.
parse_nws_grid <- function(props) {
  layer <- function(name, scale = 1) {
    v <- props[[name]]$values
    if (length(v) == 0) return(data.frame(time = as.POSIXct(character(), tz = "UTC"), value = numeric()))
    parts <- lapply(v, function(e) {
      p <- strsplit(e$validTime, "/", fixed = TRUE)[[1]]
      t0 <- as.POSIXct(sub("([+-]\\d\\d):(\\d\\d)$", "\\1\\2", p[1]), format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")
      n <- max(iso_hours(p[2]), 1)
      data.frame(time = t0 + 3600 * (seq_len(n) - 1),
                 value = if (is.null(e$value)) NA_real_ else e$value * scale)
    })
    do.call(rbind, parts)
  }
  kmh <- if (identical(props$windGust$uom, "wmoUnit:m_s-1")) 1 else 1 / 3.6
  g <- layer("windGust", kmh)
  w <- layer("windSpeed", if (identical(props$windSpeed$uom, "wmoUnit:m_s-1")) 1 else 1 / 3.6)
  d <- layer("windDirection")
  r <- layer("relativeHumidity")
  hours <- sort(unique(c(g$time, w$time, d$time, r$time)))
  pick <- function(x) x$value[match(hours, x$time)]
  tibble::tibble(time = hours, wind_ms = pick(w), gust_ms = pick(g), dir_from_deg = pick(d),
                 rh_pct = pick(r))
}

# Hours in an ISO 8601 duration such as "PT4H" or "P1DT6H".
iso_hours <- function(x) {
  num <- function(re) {
    v <- regmatches(x, regexpr(re, x))
    if (length(v) == 0) 0 else as.numeric(sub("[A-Z]$", "", v))
  }
  24 * num("[0-9]+D") + num("[0-9]+H")
}

#' Segments to watch under the coming fire weather
#'
#' Flags forecast hours that meet the fire-weather criteria
#' ([fire_wind_hours()] thresholds, normally the climatological ones) or fall
#' inside an active Red Flag Warning, then reports per segment which strike
#' trees those winds would throw into the line ([wind_fall_exposure()]
#' geometry) and whether the segment's grown-in canopy is dry
#' ([canopy_dryness()]), when present.
#'
#' @param risk Output of [wind_fall_exposure()] (trees need `bearing_deg`
#'   and `arc_*_deg`).
#' @param forecast Output of [nws_forecast()].
#' @param alerts Output of [nws_alerts()], or `NULL`.
#' @param min_gust_ms,max_rh Fire-weather thresholds; default to those used
#'   for the climatology in `attr(risk$segments, "wind")`.
#' @param spread_deg Fall-direction allowance, as in [wind_fall_exposure()].
#' @param bound `"lo"` or `"hi"`: which conductor bound defines the strike
#'   trees and their arcs.
#' @param now Forecast hours before the start of this hour are already past
#'   and are dropped: NWS gridpoint layers begin at the start of the current
#'   period, hours before the request. Set it in tests to pin the clock.
#' @return A tibble, one row per segment with any flagged exposure, ordered
#'   by trees exposed: `seg_id`, `first_hour`, `n_hours`, `max_gust_ms`,
#'   `min_rh_pct` (`NA` when the flagged hours carry no value, e.g. a Red
#'   Flag Warning over hours with no gust), `n_trees_exposed`, `red_flag`,
#'   `dry_grow_in`. Attribute `hours` holds the flagged forecast hours and
#'   attribute `settings` the thresholds, bound, clock and the number of past
#'   hours dropped, so a writer can record what the list was made with.
#' @export
forecast_watchlist <- function(risk, forecast, alerts = NULL, min_gust_ms = NULL, max_rh = NULL,
                               spread_deg = NULL, bound = c("lo", "hi"), now = Sys.time()) {
  bound <- match.arg(bound)
  info <- attr(risk$segments, "wind")
  min_gust_ms <- min_gust_ms %||% info$min_gust_ms
  max_rh <- max_rh %||% info$max_rh %||% 30
  spread_deg <- spread_deg %||% info$spread_deg %||% 15
  finite_scalar <- function(x) length(x) == 1 && is.numeric(x) && is.finite(x)
  if (!finite_scalar(min_gust_ms)) {
    rlang::abort("`min_gust_ms` must be a finite number (none in `risk`'s wind climatology either).")
  }
  if (!(length(max_rh) == 1 && is.numeric(max_rh) && !is.na(max_rh))) {
    rlang::abort("`max_rh` must be a number (or Inf to keep every humidity).")
  }
  if (!finite_scalar(spread_deg)) rlang::abort("`spread_deg` must be a finite number.")
  if (!all(c("bearing_deg", paste0("arc_", bound, "_deg")) %in% names(risk$trees))) {
    rlang::abort("`risk$trees` has no hitting arcs: run `wind_fall_exposure()` first.")
  }

  past <- !is.na(forecast$time) & forecast$time < trunc(now, "hours")
  forecast <- forecast[!past, ]

  rf <- alerts[alerts$event %in% "Red Flag Warning", , drop = FALSE]
  in_rf <- vapply(forecast$time, function(t) {
    any(!is.na(rf$onset) & rf$onset <= t & (is.na(rf$ends) | rf$ends >= t))
  }, FALSE)
  windy <- !is.na(forecast$gust_ms) & forecast$gust_ms >= min_gust_ms &
    !is.na(forecast$rh_pct) & forecast$rh_pct <= max_rh
  hours <- forecast[(windy | in_rf) & !is.na(forecast$dir_from_deg), ]
  hours$red_flag <- in_rf[(windy | in_rf) & !is.na(forecast$dir_from_deg)]

  settings <- list(min_gust_ms = min_gust_ms, max_rh = max_rh, spread_deg = spread_deg,
                   bound = bound, now = now, n_past_hours_dropped = sum(past),
                   n_forecast_hours = nrow(forecast))
  empty <- tibble::tibble(seg_id = integer(), first_hour = as.POSIXct(character(), tz = "UTC"),
                          n_hours = integer(), max_gust_ms = numeric(), min_rh_pct = numeric(),
                          n_trees_exposed = integer(), red_flag = logical(), dry_grow_in = logical())
  attr(empty, "hours") <- hours
  attr(empty, "settings") <- settings
  if (nrow(hours) == 0) return(empty)

  trees <- risk$trees
  strike <- trees[[paste0("strike_", bound)]]
  arc <- trees[[paste0("arc_", bound, "_deg")]]
  conv <- info$convergence_deg %||% grid_convergence(sf::st_as_sfc(sf::st_bbox(risk$segments)))
  wind_to <- (hours$dir_from_deg + 180 + conv) %% 360
  # trees x hours: does this hour's wind throw this strike tree into the line?
  exposed <- vapply(seq_along(wind_to), function(j) {
    strike & !is.na(arc) & ang_diff(wind_to[j], trees$bearing_deg) <= arc + spread_deg
  }, logical(nrow(trees)))
  exposed <- matrix(exposed, nrow = nrow(trees))

  seg <- sf::st_drop_geometry(risk$segments)
  dry_col <- if (bound == "lo") "dry_grow_in_lo" else "dry_grow_in"
  dry <- seg[[dry_col]] %||% rep(NA, nrow(seg))
  rows <- lapply(seq_len(nrow(seg)), function(i) {
    s <- seg$seg_id[i]
    ti <- trees$seg_id == s
    hit_h <- if (any(ti)) colSums(exposed[ti, , drop = FALSE]) > 0 else rep(FALSE, nrow(hours))
    dry_i <- isTRUE(dry[i])
    if (!any(hit_h) && !dry_i) return(NULL)
    hh <- if (any(hit_h)) hit_h else rep(TRUE, nrow(hours)) # dry canopy: every flagged hour
    tibble::tibble(seg_id = s, first_hour = min(hours$time[hh]), n_hours = sum(hh),
                   max_gust_ms = finite_max(hours$gust_ms[hh]),
                   min_rh_pct = finite_min(hours$rh_pct[hh]),
                   n_trees_exposed = if (any(ti)) sum(rowSums(exposed[ti, , drop = FALSE]) > 0) else 0L,
                   red_flag = any(hours$red_flag[hh]), dry_grow_in = dry_i)
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) return(empty)
  out <- out[order(-out$n_trees_exposed, -out$dry_grow_in, out$first_hour), ]
  attr(out, "hours") <- hours
  attr(out, "settings") <- settings
  out
}

# max()/min() that give NA, not +/-Inf and a warning, when nothing is finite
# (a Red Flag Warning can flag hours whose gust or humidity is missing).
finite_max <- function(x) { x <- x[is.finite(x)]; if (length(x)) max(x) else NA_real_ }
finite_min <- function(x) { x <- x[is.finite(x)]; if (length(x)) min(x) else NA_real_ }
