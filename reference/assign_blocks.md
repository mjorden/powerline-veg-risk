# Assign points to spatial blocks and CV folds

Assign points to spatial blocks and CV folds

## Usage

``` r
assign_blocks(feat, crs, block_m = 100, n_folds = 5, seed = 1)
```

## Arguments

- feat:

  A features table with `X`, `Y`.

- crs:

  CRS of the coordinates.

- block_m:

  Block edge length in metres.

- n_folds:

  Number of folds.

- seed:

  RNG seed for fold assignment.

## Value

`feat` with integer columns `block` and `fold`.
