# Fetch overhead power lines from OpenStreetMap

Fetch overhead power lines from OpenStreetMap

## Usage

``` r
osm_power_lines(
  aoi = NULL,
  ids = NULL,
  overpass_url = "https://overpass-api.de/api/interpreter"
)
```

## Arguments

- aoi:

  An `sf`/`sfc` object or `bbox` defining the search window.

- ids:

  Optional OSM way ids; if given, only these ways are returned.

- overpass_url:

  Overpass endpoint.

## Value

An `sf` LINESTRING data frame (EPSG:4326) with `osm_id`, `name`,
`voltage_kv`, `operator`.
