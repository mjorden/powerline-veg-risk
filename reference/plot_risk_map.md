# Map of canopy height, segment priority, and strike trees

Segment colour is the canopy area inside the clearance envelope under
the pessimistic (lower) conductor bound - where to verify first, not a
finding. Zero is drawn as absence (a thin neutral line), never as the
pale end of the risk ramp. Line type is the confidence: dashed where the
tier depends on the unknown conductor elevation, dotted where too little
of the corridor was observed to claim no risk (`"no data"`). Cells the
LiDAR did not observe are drawn grey and their area is reported, so
unseen never reads as clear. Strike trees are ink dots (both bounds) or
paper dots (one bound); supports used for the upper bound are crosses.

## Usage

``` r
plot_risk_map(
  rasters,
  risk,
  structures = NULL,
  encroach_limits = c(0, NA),
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

  OSM structures and line vertices (`sf`), optional.

- encroach_limits:

  Range of the encroachment ramp (m^2). The lower end is zero; an `NA`
  upper end is the largest value on the map. Set both to share one ramp
  across maps.

- title:

  Plot title.

- source:

  Data credit shown in the subtitle.

- file:

  Output PNG path, or `NULL` to return the plot.
