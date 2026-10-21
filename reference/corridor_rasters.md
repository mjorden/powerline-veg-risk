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
corridor_rasters(
  las,
  pred,
  res_m = 1,
  profile = NULL,
  envelope_m = 15,
  below_m = 1,
  min_linearity = 0.6,
  gap_m = 1.5,
  drop = NULL,
  void_m = 5
)
```

## Arguments

- las:

  Height-normalised `LAS` from
  [`read_corridor()`](https://mjorden.github.io/powerline-veg-risk/reference/read_corridor.md).

- pred:

  Output of
  [`predict_points()`](https://mjorden.github.io/powerline-veg-risk/reference/predict_points.md)
  (with the weak `label` column and the `linearity_k10` feature).

- res_m:

  Raster resolution in metres.

- profile:

  Optional output of
  [`conductor_profile()`](https://mjorden.github.io/powerline-veg-risk/reference/conductor_profile.md).

- envelope_m:

  Half-width of the conductor envelope (metres).

- below_m:

  Depth below the measured conductor still treated as conductor returns
  (sag between bins, bundle spacing).

- min_linearity:

  Linearity needed for an envelope point to count as a conductor return.

- gap_m:

  Empty space beneath a candidate cluster for it to count as suspended.

- drop:

  Optional logical vector over `pred` rows of points to keep out of the
  canopy model (e.g. vendor-classified buildings). These are known not
  to be canopy, so they do not make a cell unobserved.

- void_m:

  Width of the square window (metres) that must contain no LiDAR return
  of any class for a cell to count as a void. Wide enough that ordinary
  point spacing never empties it (3DEP QL2 is \>= 2 pts/m^2).

## Value

A list with `dtm` (ground elevation) and `chm` (canopy height), both
`SpatRaster` in metres, `unobserved` (logical `SpatRaster`), `void`
(logical `SpatRaster`, the voids alone), `n_conductor_excluded` and
`n_uncertain_excluded` (points left out of the canopy model as
uncertain, conductor exclusions included).

## Details

Conductor returns that cross over canopy are not "suspended" (there is
canopy below them), so the rules can label them vegetation. When a
conductor `profile` is supplied, points are excluded as conductor
returns only if they are (a) within `envelope_m` of the centreline where
the conductor is measured, (b) at or above the measured conductor
elevation minus `below_m`, and (c) wire-like: either locally linear
(`linearity_k10 >= min_linearity`) or locally suspended - no return of
any kind in the `gap_m` layer just beneath the conductor band (measured
conductor elevation minus `below_m`) within its 3 x 3 m neighbourhood
(bundled conductors form ribbons, not lines, so linearity alone misses
them). A tree crown that reaches wire height has foliage below it and
stays in the canopy model, as does canopy within `gap_m` of a conductor
(which the clearance target flags anyway). Keep `envelope_m` no wider
than the grow-in zone used in
[`assess_risk()`](https://mjorden.github.io/powerline-veg-risk/reference/assess_risk.md),
or tall side trees could lose their tops before the fall-in test.

A cell with no canopy is bare ground only if the LiDAR saw it as such.
Cells are returned as `unobserved` (unknown, not bare ground) when
either

- they held points kept out of the canopy model whose class is
  uncertain - unlabelled points (the margins around wire / structure /
  building labels and abstained near-line candidates), points the
  classifier and the rules disagree on, and conductor-envelope
  exclusions - and no canopy remains; or

- they are LiDAR voids: no return of any class within a `void_m` square
  window (missing or truncated tiles, water, dropouts). The TIN terrain
  model interpolates straight across voids, so they would otherwise read
  as bare ground.

Points the rules labelled wire, structure or building are not uncertain:
a wire label requires an observed air gap beneath it, and structures and
buildings are not canopy.
