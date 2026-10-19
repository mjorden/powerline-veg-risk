# Classify all featurised points

Classify all featurised points

## Usage

``` r
predict_points(model, feat)
```

## Arguments

- model:

  A model from
  [`train_point_classifier()`](https://mjorden.github.io/powerline-veg-risk/reference/train_point_classifier.md).

- feat:

  Features table.

## Value

`feat` with `pred` (factor) and one `p_<class>` probability column per
class (prior-corrected, see
[`classify_probs()`](https://mjorden.github.io/powerline-veg-risk/reference/classify_probs.md)).
