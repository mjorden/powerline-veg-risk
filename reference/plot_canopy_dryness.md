# Map of dry-season canopy greenness and dry grown-in segments

Landsat pixels are drawn at their 30 m footprint, coloured by the index
that drives `dry_canopy`; pixels below the canopy-fraction cut-off
(mostly cleared right-of-way) are grey. Segments are coloured by the
combined screen.

## Usage

``` r
plot_canopy_dryness(dryness, title = NULL, file = NULL)
```

## Arguments

- dryness:

  Output of
  [`canopy_dryness()`](https://mjorden.github.io/powerline-veg-risk/reference/canopy_dryness.md).

- title:

  Plot title; `NULL` states how many grown-in segments have dry canopy.

- file:

  Output PNG path, or `NULL`.
