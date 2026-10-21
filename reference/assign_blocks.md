# Assign points to spatial blocks and CV folds

Assign points to spatial blocks and CV folds

## Usage

``` r
assign_blocks(feat, crs = NULL, block_m = 100, n_folds = 5, seed = 1)
```

## Arguments

- feat:

  A features table with `X`, `Y`.

- crs:

  CRS of the coordinates; defaults to the one recorded by
  [`point_features()`](https://mjorden.github.io/powerline-veg-risk/reference/point_features.md)
  and must agree with it when both are given.

- block_m:

  Block edge length in metres.

- n_folds:

  Number of folds.

- seed:

  RNG seed for fold assignment.

## Value

`feat` with integer columns `block` and `fold`. Block ids are numbered
by position (west to east, then south to north), so they do not depend
on row order.
