# Ground and conductor profile along the line

Ground and conductor profile along the line

## Usage

``` r
plot_profile(profile, risk = NULL, attach_m = NA, file = NULL)
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

- file:

  Output PNG path, or `NULL`.
