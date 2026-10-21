# Ground and conductor profile along the line

Where the conductor was classified from returns it is drawn as a line
(the per-5 m-bin elevation, interpolated across gaps of at most
`max_gap_m`); elsewhere the band between the code-minimum floor and the
chord between supports brackets it. The two never join: a switch between
measured and bounded is a break in the drawing, not a vertical in the
conductor. Strike trees, when `risk` is given, sit at their base
elevation along the line.

## Usage

``` r
plot_profile(profile, risk = NULL, attach_m = NA, line_id = NULL, file = NULL)
```

## Arguments

- profile:

  Output of
  [`conductor_profile()`](https://mjorden.github.io/powerline-veg-risk/reference/conductor_profile.md).

- risk:

  Output of
  [`assess_risk()`](https://mjorden.github.io/powerline-veg-risk/reference/assess_risk.md),
  optional; strike trees are drawn at their base elevation.

- attach_m:

  Attachment height used for the upper bound (for the subtitle).

- line_id:

  Which line of a multi-line corridor to draw; the first by default,
  with a message when others exist.

- file:

  Output PNG path, or `NULL`.
