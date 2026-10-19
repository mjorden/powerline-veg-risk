# Cross-validation metrics: spatial-block vs random folds

Cross-validation metrics: spatial-block vs random folds

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
