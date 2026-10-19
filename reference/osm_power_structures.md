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

An `sf` POINT data frame (EPSG:4326) with `osm_id` and `type`.
