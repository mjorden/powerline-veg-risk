# Hourly National Weather Service forecast for a corridor

Looks up the NWS forecast grid cell (2.5 km) at the centroid of `aoi`
and returns its hourly wind, gust, direction and humidity for the next
~7 days. United States only; free, no key.

## Usage

``` r
nws_forecast(aoi, api = nws_api)
```

## Arguments

- aoi:

  An `sf`/`sfc` object (any CRS) or a `bbox`.

- api:

  NWS API root.

## Value

A tibble with the same columns as
[`wind_history()`](https://mjorden.github.io/powerline-veg-risk/reference/wind_history.md);
attributes `office`, `grid` and `updated`.
