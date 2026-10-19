# Build terrain and vegetation-only canopy height rasters

The canopy height model (CHM) is built from *consensus* vegetation:
points the classifier predicts as vegetation and the weak-label rules
also call vegetation. Points the rules labelled wire / structure /
building, and the unlabelled margins and abstained near-line candidates,
are left out. The prior-corrected classifier rarely predicts the rare
classes, so using its argmax alone would let conductor returns over
canopy set the CHM to the conductor's height - zero clearance by
construction.

## Usage

``` r
corridor_rasters(las, pred, res_m = 1)
```

## Arguments

- las:

  Height-normalised `LAS` from
  [`read_corridor()`](https://mjorden.github.io/powerline-veg-risk/reference/read_corridor.md).

- pred:

  Output of
  [`predict_points()`](https://mjorden.github.io/powerline-veg-risk/reference/predict_points.md)
  (with the weak `label` column).

- res_m:

  Raster resolution in metres.

## Value

A list with `dtm` (ground elevation) and `chm` (canopy height), both
`SpatRaster` in metres.
