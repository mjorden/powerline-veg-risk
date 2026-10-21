# Cross-section of classified points perpendicular to the line

Cross-section of classified points perpendicular to the line

## Usage

``` r
plot_cross_section(
  las,
  pred,
  lines,
  file = NULL,
  at = 0.5,
  width_m = 4,
  half_len_m = 40,
  line_id = NULL
)
```

## Arguments

- las:

  Height-normalised `LAS`.

- pred:

  Output of
  [`predict_points()`](https://mjorden.github.io/powerline-veg-risk/reference/predict_points.md).

- lines:

  Corridor lines (`sf`, same CRS as `las`).

- file:

  Output PNG path, or `NULL`.

- at:

  Fraction along the line at which to cut the section.

- width_m:

  Slab thickness (metres, along the line).

- half_len_m:

  Section half-length (metres, across the line).

- line_id:

  Which merged line of a multi-line corridor to cut; the first by
  default, with a message when others exist.
