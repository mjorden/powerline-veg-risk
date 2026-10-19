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

`sf` with `seg_id`, `line_id`, `length_m`.
