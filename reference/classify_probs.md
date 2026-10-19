# Prior-corrected class probabilities

Prior-corrected class probabilities

## Usage

``` r
classify_probs(model, feat)
```

## Arguments

- model:

  A model from
  [`train_point_classifier()`](https://mjorden.github.io/powerline-veg-risk/reference/train_point_classifier.md).

- feat:

  Features table.

## Value

Matrix of class probabilities at the training-set prevalence.
