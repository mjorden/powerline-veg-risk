# Model conductor elevation along the line

Conductor returns are points the wire rule labelled (`label == "wire"`)
or that the classifier calls wire with probability \>= `min_p_wire`.
Returns within `structure_mask_m` of a support are ignored (guy wires,
crossarms and insulators there are elevated and linear too). Each
`bin_m` chainage bin takes a low quantile (`q`) of return elevations;
bins below the lower bound (physically non-compliant, so an artefact) or
implying a slope steeper than `max_slope` to both neighbours are
rejected. Surviving bins are interpolated across gaps of at most
`max_gap_m` (`src = "measured"`). Elsewhere the conductor is bracketed
(`src = "bounded"`):

## Usage

``` r
conductor_profile(
  pred,
  segments,
  dtm,
  supports = NULL,
  step_m = 1,
  search_m = 15,
  min_p_wire = 0.9,
  structure_mask_m = 8,
  bin_m = 5,
  min_bin_points = 3,
  q = 0.25,
  max_slope = 0.2,
  max_gap_m = 30,
  min_ground_clear_m = 4.9,
  attach_m = 20,
  max_span_m = 500
)
```

## Arguments

- pred:

  Output of
  [`predict_points()`](https://mjorden.github.io/powerline-veg-risk/reference/predict_points.md).

- segments:

  Output of
  [`segment_lines()`](https://mjorden.github.io/powerline-veg-risk/reference/segment_lines.md).

- dtm:

  Ground elevation raster (metres), from
  [`corridor_rasters()`](https://mjorden.github.io/powerline-veg-risk/reference/corridor_rasters.md).

- supports:

  Optional `sf` points of support structures.

- step_m:

  Vertex spacing of the conductor model (metres).

- search_m:

  Wire points farther than this from the line are ignored.

- min_p_wire:

  Classifier probability needed for a point the rule did not label to
  count as a conductor return.

- structure_mask_m:

  Returns this close to a support are ignored.

- bin_m, min_bin_points, q:

  Chainage bin width, minimum returns per bin, and the quantile of
  return elevations used per bin.

- max_slope:

  Maximum plausible conductor slope (rise / run) between adjacent
  measured bins.

- max_gap_m:

  Largest gap between measured bins that is interpolated.

- min_ground_clear_m, attach_m, max_span_m:

  Bounds parameters, metres.

## Value

data.frame of vertices: `line_id`, `x`, `y`, `s_m`, `seg_id`, `ground`,
`z_lo`, `z_hi`, `src`.

## Details

- lower bound: ground + `min_ground_clear_m`. NESC Table 232-1 vertical
  clearance for a 115 kV line is roughly 4.9 m over land accessible only
  to pedestrians (more over roads), so a compliant line is not lower.

- upper bound: with `supports`, the straight chord between the supports
  either side of a station, each at ground + `attach_m`. A conductor
  sags below the chord between its attachments, so it cannot be higher
  unless attachments exceed `attach_m`. Where the next support lies
  outside the data the upper bound is unknown and set to `Inf` (no
  optimistic claim). Without `supports`, the highest chord between any
  two points no more than `max_span_m` apart is used, which is only an
  upper bound if real spans are no longer than that.

A terrain-following model (constant height above the ground below) is
wrong where a span crosses a gully; the bounds make that uncertainty
explicit instead of hiding it.
