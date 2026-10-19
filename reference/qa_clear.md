# Clear-sky land pixels from a Landsat Collection 2 QA_PIXEL band

A pixel is kept when none of these bits are set: fill (0), dilated cloud
(1), cirrus (2), cloud (3), cloud shadow (4), snow (5), water (7). Water
is dropped too: its negative NDVI would read as very dry canopy.

## Usage

``` r
qa_clear(qa)
```

## Arguments

- qa:

  Integer vector of QA_PIXEL values.

## Value

Logical vector, `TRUE` for usable pixels (`NA` stays `NA`).
