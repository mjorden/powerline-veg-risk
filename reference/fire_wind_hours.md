# Select dry, high-wind ("fire-weather") hours

Keeps hours with gusts at or above `min_gust_ms` (default: the
`gust_quantile` of the whole record) and relative humidity at or below
`max_rh`. These are the conditions under which a tree blown into the
line can start a fire that spreads.

## Usage

``` r
fire_wind_hours(wind, gust_quantile = 0.95, min_gust_ms = NULL, max_rh = 30)
```

## Arguments

- wind:

  Output of
  [`wind_history()`](https://mjorden.github.io/powerline-veg-risk/reference/wind_history.md)
  or
  [`nws_forecast()`](https://mjorden.github.io/powerline-veg-risk/reference/nws_forecast.md).

- gust_quantile:

  Quantile of the record used as the gust threshold when `min_gust_ms`
  is `NULL`.

- min_gust_ms:

  Absolute gust threshold (m/s); overrides the quantile.

- max_rh:

  Maximum relative humidity (percent); `Inf` keeps all.

## Value

The selected rows, with attributes `min_gust_ms`, `max_rh` and
`n_record` (hours in the full record).
