# Assign weak labels to featurised points

Assign weak labels to featurised points

## Usage

``` r
weak_labels(
  feat,
  crs,
  lines,
  structures = NULL,
  buildings = NULL,
  cell_m = 1,
  gap_floor_m = 2,
  layer_m = 4,
  gap_m = 2,
  wire_min_m = 6,
  wire_search_m = 12,
  run_half_m = 10,
  min_run = 6,
  min_extent_m = 12,
  row_m = 1.5,
  min_occupancy = 0.4,
  structure_radius_m = 3,
  building_shrink_m = 1,
  margin_m = 2
)
```

## Arguments

- feat:

  Output of
  [`point_features()`](https://mjorden.github.io/powerline-veg-risk/reference/point_features.md).

- crs:

  CRS of the point cloud.

- lines, structures, buildings:

  `sf` layers from OSM (any CRS).

- cell_m:

  2D cell size for the air-gap test.

- gap_floor_m:

  Points below this height are ignored by the air-gap test (grass,
  fences, shrubs). Cannot be lower than the featurisation floor.

- layer_m:

  Maximum vertical thickness of a suspended cell's points (allows
  vertically stacked phases and a shield wire).

- gap_m:

  Depth of empty space required beneath a cell's lowest point across its
  3 x 3 window.

- wire_min_m:

  Minimum height for a wire label.

- wire_search_m:

  Wire labels are only assigned within this horizontal distance of a
  mapped line (covers OSM misalignment and phase spacing).

- run_half_m, row_m, min_run, min_extent_m, min_occupancy:

  Along-line run test. For each candidate cell, its "row" is the
  candidates within `run_half_m` chainage and `row_m` perpendicular
  offset of it (one conductor; parallel phases form separate rows). The
  row qualifies if it has at least `min_run` cells, spans at least
  `min_extent_m` along the line, and occupies at least `min_occupancy`
  of the 1 m chainage bins across that span. All members of a qualifying
  row are wire.

- structure_radius_m:

  Radius around pole/tower nodes.

- building_shrink_m:

  Inward buffer applied to building footprints.

- margin_m:

  Width of the unlabelled margin around non-vegetation labels.

## Value

`feat` with a factor column `label` (levels vegetation, wire, structure,
building; NA = unlabelled).
