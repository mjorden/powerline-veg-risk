# Ground and conductor profile along the line

Ground and conductor profile along the line

## Usage

``` r
plot_profile(profile, risk = NULL, file = NULL)
```

## Arguments

- profile:

  Output of
  [`conductor_profile()`](https://mjorden.github.io/powerline-veg-risk/reference/conductor_profile.md).

- risk:

  Output of
  [`assess_risk()`](https://mjorden.github.io/powerline-veg-risk/reference/assess_risk.md),
  optional; strike trees are drawn at their base elevation.

- file:

  Output PNG path, or `NULL`.
