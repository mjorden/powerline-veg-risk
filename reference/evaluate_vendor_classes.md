# Score labels against vendor-delivered ASPRS classes

Some 3DEP deliveries classify vegetation (ASPRS 3-5) and buildings (6).
Those vendor classes are independent of this package's weak labels, so
they provide a ground-truth check for the classes they cover. Only
points whose vendor class is in `map` are scored; vendor "unclassified"
points are excluded. Vegetation usually dominates (prevalence near 1),
so its F1 cannot show skill: an always-"vegetation" baseline is reported
alongside, with balanced accuracy and Cohen's kappa over the mapped
classes. A class that is never predicted has precision 0, not NA.

## Usage

``` r
evaluate_vendor_classes(
  labels,
  vendor_class,
  map = list(vegetation = 3:5, building = 6L)
)
```

## Arguments

- labels:

  Factor of labels to score (e.g. `pred$pred` or `feat$label`).

- vendor_class:

  Integer ASPRS class of the same points.

- map:

  Named list mapping package labels to vendor class codes.

## Value

A list with `metrics` (per-class precision, recall, F1, n, plus
`balanced_accuracy` and `kappa`), `baseline` (the same for predicting
the majority class everywhere) and `confusion`.
