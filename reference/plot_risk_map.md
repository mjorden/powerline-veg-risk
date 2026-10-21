# Map of canopy height, segment priority, and strike trees

Segment colour is the canopy area inside the clearance envelope under
the pessimistic (lower) conductor bound - where to verify first, not a
finding; line type is the confidence (solid = measured conductor or same
tier under both bounds, dashed = tier depends on the unknown conductor
elevation). Segments tiered `"no data"` (too little of the corridor
observed to claim no risk) are drawn grey and dotted instead of on the
encroachment scale, so they never read as clear.

## Usage

``` r
plot_risk_map(
  rasters,
  risk,
  structures = NULL,
  title = "Vegetation risk along the line",
  source = "USGS 3DEP LiDAR",
  file = NULL
)
```

## Arguments

- rasters:

  Output of
  [`corridor_rasters()`](https://mjorden.github.io/powerline-veg-risk/reference/corridor_rasters.md).

- risk:

  Output of
  [`assess_risk()`](https://mjorden.github.io/powerline-veg-risk/reference/assess_risk.md).

- structures:

  OSM structures (`sf`), optional.

- title:

  Plot title.

- source:

  Data credit shown in the subtitle.

- file:

  Output PNG path, or `NULL` to return the plot.
