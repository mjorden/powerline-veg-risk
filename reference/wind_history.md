# Hourly historical wind and humidity for a corridor

Fetches hourly 10 m wind speed, gusts and direction and 2 m relative
humidity from the Open-Meteo historical archive (ERA5 reanalysis,
roughly 10-25 km grid; free, no key, CC BY 4.0) at the centroid of
`aoi`.

## Usage

``` r
wind_history(aoi, start_date, end_date, url = openmeteo_archive)
```

## Arguments

- aoi:

  An `sf`/`sfc` object (any CRS) or a `bbox`.

- start_date, end_date:

  Dates (or `"YYYY-MM-DD"` strings).

- url:

  Archive endpoint.

## Value

A tibble: `time` (UTC), `wind_ms`, `gust_ms`, `dir_from_deg` (direction
the wind blows *from*, degrees clockwise from true north) and `rh_pct`.
Attributes `lon`, `lat` give the grid cell used.

## Details

Reanalysis winds describe the regional flow. They don't resolve terrain
channelling in a canyon or gusts at a ridge crest.
