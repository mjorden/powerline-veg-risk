# Cross-validation metrics: spatial-block vs random folds

Schemes are offset within each class row so none hides another; colours
are keyed by scheme name (a subset keeps its colours) and unknown
schemes are kept, drawn neutral, with a warning. Average precision below
0.01 is printed to two significant figures, so 0.004 never reads as
0.00.

## Usage

``` r
plot_cv(metrics, file = NULL)
```

## Arguments

- metrics:

  `metrics` element of
  [`cv_point_classifier()`](https://mjorden.github.io/powerline-veg-risk/reference/cv_point_classifier.md),
  optionally with extra schemes (e.g. an ablation) stacked in.

- file:

  Output PNG path, or `NULL`.
