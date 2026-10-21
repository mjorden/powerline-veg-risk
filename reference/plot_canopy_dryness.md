# Map of dry-season canopy greenness and dry grown-in segments

Scored Landsat pixels are drawn at their 30 m footprint on a sequential
greenness ramp (dry ochre to deep olive) with the `dry_canopy` cut
marked on the key; pixels the screen did not score (too little canopy,
too little LiDAR coverage, too few clear looks) are grey. Segments are
coloured by the combined screen under the chosen conductor bound.

## Usage

``` r
plot_canopy_dryness(dryness, bound = c("hi", "lo"), title = NULL, file = NULL)
```

## Arguments

- dryness:

  Output of
  [`canopy_dryness()`](https://mjorden.github.io/powerline-veg-risk/reference/canopy_dryness.md).

- bound:

  `"hi"` (optimistic conductor, the default) or `"lo"` (pessimistic):
  which grow-in tier "grown in" refers to.

- title:

  Plot title; `NULL` states how many grown-in segments have dry canopy.

- file:

  Output PNG path, or `NULL`.
