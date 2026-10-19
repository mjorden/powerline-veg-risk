# Train a random-forest point classifier

Vegetation is subsampled to at most `n_per_class` points (it outnumbers
the other classes by orders of magnitude); every class is then weighted
by the inverse of its training frequency through ranger's
`case.weights`, so bootstrap samples are approximately class-balanced. A
forest trained that way estimates class posteriors under *equal* priors;
the true label prevalence is stored on the model (`$prior`) and
[`classify_probs()`](https://mjorden.github.io/powerline-veg-risk/reference/classify_probs.md)
re-weights posteriors by it, so decisions are made at the site's real
class mix rather than flooding the rare classes with false positives.

## Usage

``` r
train_point_classifier(
  feat,
  n_per_class = 20000,
  num_trees = 300,
  mtry = NULL,
  drop_features = NULL,
  seed = 1
)
```

## Arguments

- feat:

  Labelled features (from
  [`weak_labels()`](https://mjorden.github.io/powerline-veg-risk/reference/weak_labels.md)).

- n_per_class:

  Maximum training points per class.

- num_trees, mtry:

  Passed to
  [`ranger::ranger()`](http://imbs-hl.github.io/ranger/reference/ranger.md).

- drop_features:

  Feature columns to exclude (for ablation).

- seed:

  RNG seed.

## Value

A `ranger` model (probability forest).
