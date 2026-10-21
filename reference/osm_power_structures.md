# Fetch power-line support structures (poles, towers) from OpenStreetMap

Fetch power-line support structures (poles, towers) from OpenStreetMap

## Usage

``` r
osm_power_structures(
  aoi,
  overpass_url = "https://overpass-api.de/api/interpreter"
)
```

## Arguments

- aoi:

  An `sf`/`sfc` object or `bbox` defining the search window.

- overpass_url:

  Overpass endpoint.

## Value

An `sf` POINT data frame (EPSG:4326) with `osm_id` and `type`; zero rows
when the area has none (sf gives an empty geometry column the class
`sfc_GEOMETRY`, so test [`nrow()`](https://rdrr.io/r/base/nrow.html),
not the class).
