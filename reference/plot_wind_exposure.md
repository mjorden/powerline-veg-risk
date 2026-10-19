# Strike trees the fire-weather winds would throw into the line

Map of potential strike trees (under one conductor bound) coloured by
the share of fire-weather hours whose wind would push them into the
line, over the canopy height model, with a wind rose of those hours.

## Usage

``` r
plot_wind_exposure(
  risk,
  rasters = NULL,
  bound = c("lo", "hi"),
  title = NULL,
  file = NULL
)
```

## Arguments

- risk:

  Output of
  [`wind_fall_exposure()`](https://mjorden.github.io/powerline-veg-risk/reference/wind_fall_exposure.md).

- rasters:

  Output of
  [`corridor_rasters()`](https://mjorden.github.io/powerline-veg-risk/reference/corridor_rasters.md),
  optional (canopy backdrop).

- bound:

  `"lo"` or `"hi"`: conductor bound defining the strike trees.

- title:

  Plot title; `NULL` states the windward count.

- file:

  Output PNG path, or `NULL`.
