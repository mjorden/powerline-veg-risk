# Metres per horizontal CRS unit of a LAS object or file header

Metres per horizontal CRS unit of a LAS object or file header

## Usage

``` r
las_m_per_unit(x)
```

## Arguments

- x:

  A `LAS`, `LAScatalog`, `LASheader`, or anything with an
  [`sf::st_crs()`](https://r-spatial.github.io/sf/reference/st_crs.html).

## Value

Numeric scalar (1 for metre CRSs, 0.3048006 for US survey feet).
