# Build a corridor polygon around power lines

Build a corridor polygon around power lines

## Usage

``` r
line_corridor(lines, crs, half_width_m = 40)
```

## Arguments

- lines:

  `sf` lines (any CRS).

- crs:

  Target CRS (normally the point cloud's).

- half_width_m:

  Corridor half-width in metres.

## Value

An `sfc` POLYGON in `crs`.
