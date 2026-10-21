# Segments to watch under the coming fire weather

Flags forecast hours that meet the fire-weather criteria
([`fire_wind_hours()`](https://mjorden.github.io/powerline-veg-risk/reference/fire_wind_hours.md)
thresholds, normally the climatological ones) or fall inside an active
Red Flag Warning, then reports per segment which strike trees those
winds would throw into the line
([`wind_fall_exposure()`](https://mjorden.github.io/powerline-veg-risk/reference/wind_fall_exposure.md)
geometry) and whether the segment's grown-in canopy is dry
([`canopy_dryness()`](https://mjorden.github.io/powerline-veg-risk/reference/canopy_dryness.md)),
when present.

## Usage

``` r
forecast_watchlist(
  risk,
  forecast,
  alerts = NULL,
  min_gust_ms = NULL,
  max_rh = NULL,
  spread_deg = NULL,
  bound = c("lo", "hi"),
  now = Sys.time()
)
```

## Arguments

- risk:

  Output of
  [`wind_fall_exposure()`](https://mjorden.github.io/powerline-veg-risk/reference/wind_fall_exposure.md)
  (trees need `bearing_deg` and `arc_*_deg`).

- forecast:

  Output of
  [`nws_forecast()`](https://mjorden.github.io/powerline-veg-risk/reference/nws_forecast.md).

- alerts:

  Output of
  [`nws_alerts()`](https://mjorden.github.io/powerline-veg-risk/reference/nws_alerts.md),
  or `NULL`.

- min_gust_ms, max_rh:

  Fire-weather thresholds; default to those used for the climatology in
  `attr(risk$segments, "wind")`.

- spread_deg:

  Fall-direction allowance, as in
  [`wind_fall_exposure()`](https://mjorden.github.io/powerline-veg-risk/reference/wind_fall_exposure.md).

- bound:

  `"lo"` or `"hi"`: which conductor bound defines the strike trees and
  their arcs.

- now:

  Forecast hours before the start of this hour are already past and are
  dropped: NWS gridpoint layers begin at the start of the current
  period, hours before the request. Set it in tests to pin the clock.

## Value

A tibble, one row per segment with any flagged exposure, ordered by
trees exposed: `seg_id`, `first_hour`, `n_hours`, `max_gust_ms`,
`min_rh_pct` (`NA` when the flagged hours carry no value, e.g. a Red
Flag Warning over hours with no gust), `n_trees_exposed`, `red_flag`,
`dry_grow_in`. Attribute `hours` holds the flagged forecast hours and
attribute `settings` the thresholds, bound, clock and the number of past
hours dropped, so a writer can record what the list was made with.
