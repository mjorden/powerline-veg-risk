# Compute per-point classification features

Compute per-point classification features

## Usage

``` r
point_features(las, k = c(10L, 30L), min_height_m = 2)
```

## Arguments

- las:

  A height-normalised `LAS` (see
  [`read_corridor()`](https://mjorden.github.io/powerline-veg-risk/reference/read_corridor.md)).

- k:

  Neighbourhood sizes for the multi-scale eigenvalue features.

- min_height_m:

  Points below this height above ground are not featurised (they are
  ground / low cover, handled by the ground class).

## Value

A `data.table` with `pid` (row index into `las@data`), `X`, `Y`, `Z`,
and feature columns. Attributes `crs` (the CRS of `las`), `k` and
`features` (the predictor column names) travel with the table through
[`weak_labels()`](https://mjorden.github.io/powerline-veg-risk/reference/weak_labels.md),
[`assign_blocks()`](https://mjorden.github.io/powerline-veg-risk/reference/assign_blocks.md)
and
[`predict_points()`](https://mjorden.github.io/powerline-veg-risk/reference/predict_points.md).
