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
  min_encroach_m2 = 5,
  coverage_m = wire_zone_m,
  min_observed = 0.75
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
  structure's across-line width. Masked cells are excluded from cover
  and clearance and trees there are not scored, but they count as
  observed for `frac_observed` (a known structure, not a data gap).

- min_encroach_m2:

  Canopy area inside the clearance envelope needed to call a segment
  grow-in (guards against single-cell artefacts).

- coverage_m:

  Half-width of the band over which LiDAR coverage is measured
  (`frac_observed`). Set it to the corridor half-width so that voids
  beside the line, where strike trees stand, count too.

- min_observed:

  A segment whose observed share of either the `coverage_m` band or the
  `under_line_m` zone is below this, and that would otherwise be
  `"none"`, is tiered `"no data"`: absence of risk cannot be claimed
  where the LiDAR did not see the ground.

## Value

A list: `segments` (`sf`, one row per segment) and `trees` (`sf`
treetops: `tree_id` (the treetop's position to 0.1 CRS units, stable
across runs on the same data), `seg_id`, `height_m`, `dh_m` horizontal
distance to the nearest conductor, `reach_lo_m` / `reach_hi_m` the
height a tree there needs to reach the conductor under each bound (the
minimum 3D distance to any conductor vertex within reach, less the phase
offset), `dz_lo_m` / `dz_hi_m` the conductor's height above the tree's
base at that vertex, `strike_lo` / `strike_hi` / `strike` whether it
does). Columns ending `_lo` / `_hi` use the lower / upper conductor
bound. `frac_observed` and `frac_observed_under` are the shares of the
grid cells within `coverage_m` and `under_line_m` of the segment (not
past the line's ends) with an observed terrain and canopy value; cells
off the edge of the data count as unobserved, structure-masked cells as
observed (known structures, not gaps). `priority` is the tier under the
optimistic (upper) bound, i.e. what holds even if the conductor is as
high as plausible; `priority_lo` is the pessimistic tier, which
saturates wherever canopy stands under a bounded span (the lower bound
is only ~5 m above ground). Tiers are `"grow-in"`, `"fall-in"`,
`"no data"` (no risk found, but coverage below `min_observed`) and
`"none"`. A grow-in or fall-in finding stands even at low coverage,
though unseen cells could hide a more severe tier. `confidence` is
`"measured"` (conductor observed over at least half the segment *and*
the same tier under both bounds), `"robust"` (same tier under both
bounds, conductor mostly bounded), `"bound-dependent"` (the tier changes
with the bound, however much of the conductor was seen: the finding sits
in the unmeasured part) or `"low coverage"` (`"no data"` under both
bounds). `frac_measured` is reported alongside. `encroach_*_m2` is the
canopy area under the conductors inside the clearance envelope. Rows are
ordered by what holds even under the optimistic (upper) conductor
bound - encroachment, then strike trees - then by the same metrics under
the lower bound.
