# Dry-season greenness and moisture of grown-in canopy, per segment

Joins a Landsat composite to the LiDAR screen. The LiDAR canopy height
model decides *which* 30 m pixels to read and how much each one counts:

## Usage

``` r
canopy_dryness(
  composite,
  rasters,
  profile,
  risk,
  zone_m = 6,
  corridor_m = NULL,
  cover_min_m = 2,
  min_canopy_frac = 0.5,
  dry_index = c("ndvi", "ndmi"),
  dry_quantile = 0.25,
  min_canopy_m2 = 5,
  min_ref_px = 20
)
```

## Arguments

- composite:

  Output of
  [`landsat_composite()`](https://mjorden.github.io/powerline-veg-risk/reference/landsat_composite.md).

- rasters:

  Output of
  [`corridor_rasters()`](https://mjorden.github.io/powerline-veg-risk/reference/corridor_rasters.md)
  (supplies the CHM).

- profile:

  Output of
  [`conductor_profile()`](https://mjorden.github.io/powerline-veg-risk/reference/conductor_profile.md)
  (supplies the line geometry and segment ids).

- risk:

  Output of
  [`assess_risk()`](https://mjorden.github.io/powerline-veg-risk/reference/assess_risk.md).

- zone_m:

  Distance from the centreline within which canopy counts as grown in;
  normally `under_line_m` from
  [`assess_risk()`](https://mjorden.github.io/powerline-veg-risk/reference/assess_risk.md).

- corridor_m:

  Half-width of the corridor the point cloud was clipped to
  (`half_width_m` in
  [`read_corridor()`](https://mjorden.github.io/powerline-veg-risk/reference/read_corridor.md)).
  CHM cells farther from the line are outside the data and are excluded
  from canopy fractions, including the inside of bends that the terrain
  model's convex hull fills. `NULL` uses the farthest canopy return from
  the line.

- cover_min_m:

  Canopy height counted as cover.

- min_canopy_frac:

  Minimum canopy fraction of a Landsat pixel for it to be scored.

- dry_index:

  `"ndvi"` or `"ndmi"`: the index used for `dry_canopy`.

- dry_quantile:

  Percentile (0-1) at or below which a segment is `dry_canopy`.

- min_canopy_m2:

  Segments with less grown-in canopy than this (in scored pixels) get
  their indices but no percentile or `dry_canopy`.

- min_ref_px:

  Minimum canopy-dominated pixels in the corridor needed to compute
  percentiles; below it the `*_pct` columns are `NA`.

## Value

A list: `segments` (the risk segments with added columns `canopy_px`,
`canopy_m2`, `ndvi`, `ndmi`, `ndvi_pct`, `ndmi_pct`, `dry_canopy`,
`dry_grow_in`, `dry_grow_in_lo`) and `pixels` (`sf` points at Landsat
pixel centres with `ndvi`, `ndmi`, `n_obs`, `canopy_frac`, `scored`).

## Details

1.  Each Landsat pixel's canopy fraction is the share of its 1 m CHM
    cells at or above `cover_min_m`. Pixels below `min_canopy_frac` are
    mostly cleared right-of-way, road or roof, and are not scored -
    their index would describe the gap, not the trees.

2.  A segment's value is the mean of its pixels' indices weighted by how
    many of the segment's canopy cells *within `zone_m` of the line*
    fall in each pixel, so it describes the canopy under the conductors
    rather than the forest beside the right-of-way.

3.  Each segment value is ranked against every canopy-dominated pixel in
    the corridor (a percentile, `*_pct`). `dry_canopy` flags segments in
    the lowest `dry_quantile` of `dry_index`.

`dry_grow_in` combines the two screens: grow-in under the optimistic
conductor bound and dry canopy; `dry_grow_in_lo` uses the pessimistic
tier. This is a prioritisation within one corridor, not a fire-danger
rating: low NDVI over canopy can also mean thin or recently trimmed
crowns, and a 30 m pixel straddling a 20-40 m right-of-way always mixes
the corridor's canopy with its edges.
