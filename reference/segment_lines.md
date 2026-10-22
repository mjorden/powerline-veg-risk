# Split power lines into equal-length segments

Split power lines into equal-length segments

## Usage

``` r
segment_lines(lines, crs, seg_m = 50)
```

## Arguments

- lines:

  `sf` lines (any CRS).

- crs:

  Projected CRS for the output.

- seg_m:

  Target segment length in metres. Each line is split into
  `floor(length / seg_m)` equal segments, so segments are between
  `seg_m` and `2 * seg_m` long.

## Value

`sf` with `seg_id`, `line_id` (one per merged line, numbered in the
order of the first input feature touching each, not union order),
`s_from_m` / `s_to_m` (chainage of the segment's ends along its merged
line, metres), `length_m`, and, when `lines` is an `sf` carrying them,
`osm_id`, `name`, `voltage_kv` and `operator` of the nearest input line,
so a segment can be traced back to the OSM way it came from.
