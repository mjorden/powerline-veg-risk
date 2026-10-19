# Locate trees and score grow-in / fall-in risk per segment

Every metric is computed against both conductor bounds from
[`conductor_profile()`](https://mjorden.github.io/powerline-veg-risk/reference/conductor_profile.md)
(identical where the conductor is measured).

## Usage

``` r
assess_risk(
  rasters,
  profile,
  segments,
  tree_ws_m = 5,
  min_tree_m = 3,
  phase_offset_m = 3,
  growth_m = 0,
  under_line_m = 6,
  wire_zone_m = 10,
  clearance_target_m = 4.6,
  cover_min_m = 2,
  min_support = 6,
  structures = NULL,
  structure_mask_m = 8,
  min_encroach_m2 = 5
)
```

## Arguments

- rasters:

  Output of
  [`corridor_rasters()`](https://mjorden.github.io/powerline-veg-risk/reference/corridor_rasters.md).

- profile:

  Output of
  [`conductor_profile()`](https://mjorden.github.io/powerline-veg-risk/reference/conductor_profile.md).

- segments:

  Output of
  [`segment_lines()`](https://mjorden.github.io/powerline-veg-risk/reference/segment_lines.md).

- tree_ws_m:

  Local-maximum window for treetop detection (metres).

- min_tree_m:

  Minimum treetop height.

- phase_offset_m:

  Horizontal offset of the outer conductors from the mapped centreline
  (OSM maps the right-of-way centreline, not each phase).

- growth_m:

  Growth allowance added to tree heights (e.g. expected growth over a
  trim cycle).

- under_line_m:

  Horizontal distance from the centreline within which canopy counts as
  "under the conductors". Canopy there is scored as grow-in; treetops
  there are excluded from the fall-in count so the two are not
  double-counted.

- wire_zone_m:

  Half-width of the wire zone for canopy cover.

- clearance_target_m:

  Target vertical clearance between canopy and the lowest conductor. The
  default 4.6 m (15 ft) is a common utility clearance-at-time-of-work
  target; it is not the NERC FAC-003 minimum vegetation clearance
  distance, which is smaller.

- cover_min_m:

  Canopy height counted as cover.

- min_support:

  A CHM cell counts as canopy only if at least this many cells of its 3
  x 3 window are \>= `cover_min_m`. Removes 1-2 cell features (unmapped
  single poles, stray conductor returns classified as vegetation) that
  would otherwise appear as trees directly under the line. It also trims
  crown edges slightly.

- structures:

  Optional `sf` points of support structures (e.g. OSM pole/tower nodes
  and the line's own vertices, which OSM mappers place at structures).
  Canopy within `structure_mask_m` is zeroed so poles, H-frames and
  crossarms are not scored as trees under the line.

- structure_mask_m:

  Mask radius around each structure (metres); should cover the
  structure's across-line width. Masked cells are treated as unobserved
  (excluded from cover and clearance), and trees there are not scored.

- min_encroach_m2:

  Canopy area inside the clearance envelope needed to call a segment
  grow-in (guards against single-cell artefacts).

## Value

A list: `segments` (`sf`, one row per segment) and `trees` (`sf`
treetops). Columns ending `_lo` / `_hi` use the lower / upper conductor
bound. `priority` is the tier under the optimistic (upper) bound, i.e.
what holds even if the conductor is as high as plausible; `priority_lo`
is the pessimistic tier, which saturates wherever canopy stands under a
bounded span (the lower bound is only ~5 m above ground). `confidence`
is `"measured"` (conductor observed over at least half the segment),
`"robust"` (same tier under both bounds) or `"bound-dependent"`.
`encroach_*_m2` is the canopy area under the conductors inside the
clearance envelope. Rows are ordered by what holds even under the
optimistic (upper) conductor bound - encroachment, then strike trees -
then by the same metrics under the lower bound.
