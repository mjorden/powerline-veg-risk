# Cross-validate the point classifier: spatial blocks vs random folds

Every held-out non-vegetation point is scored; vegetation is scored on a
random `eval_veg_frac` sample and up-weighted by its inverse, so
precision is estimated at the site's real class prevalence. Two
threshold-free summaries are added: per-class average precision (area
under the precision-recall curve; compare it with `prevalence`, its
no-skill value) and balanced accuracy (mean per-class recall of the
argmax decision).

## Usage

``` r
cv_point_classifier(
  feat,
  n_per_class = 20000,
  num_trees = 200,
  mtry = NULL,
  drop_features = NULL,
  eval_veg_frac = 0.1,
  seed = 1
)
```

## Arguments

- feat:

  Labelled features with `fold` (from
  [`assign_blocks()`](https://mjorden.github.io/powerline-veg-risk/reference/assign_blocks.md)).

- n_per_class:

  Maximum training points per class.

- num_trees, mtry:

  Passed to
  [`ranger::ranger()`](http://imbs-hl.github.io/ranger/reference/ranger.md).

- drop_features:

  Feature columns to exclude (for ablation).

- eval_veg_frac:

  Fraction of held-out vegetation points scored.

- seed:

  RNG seed.

## Value

A list with `metrics` (per-class precision / recall / F1 and balanced
accuracy for each scheme), `confusion` (spatial-CV confusion matrix in
estimated point counts, rows = weak label, columns = prediction) and
`fold_counts` (labelled points per spatial fold).
