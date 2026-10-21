# Fetch overhead power lines from OpenStreetMap

Fetch overhead power lines from OpenStreetMap

## Usage

``` r
osm_power_lines(
  aoi = NULL,
  ids = NULL,
  power = c("line", "minor_line"),
  overpass_url = "https://overpass-api.de/api/interpreter"
)
```

## Arguments

- aoi:

  An `sf`/`sfc` object or `bbox` defining the search window.

- ids:

  Optional OSM way ids; if given, only these ways are returned.

- power:

  OSM `power=*` values to fetch within `aoi`. The default takes
  transmission (`line`) and distribution (`minor_line`) ways: both carry
  suspended conductors, and a distribution wire crossing the corridor
  would otherwise be taught to the classifier as vegetation. Underground
  `cable` is deliberately left out. Ignored when `ids` is given.

- overpass_url:

  Overpass endpoint.

## Value

An `sf` LINESTRING data frame (EPSG:4326) with `osm_id`, `name`,
`power`, `voltage_kv`, `operator`. Attributes `osm_timestamp` (the OSM
data snapshot the answer came from) and `osm_query` record the
provenance;
[`osm_power_structures()`](https://mjorden.github.io/powerline-veg-risk/reference/osm_power_structures.md)
and
[`osm_buildings()`](https://mjorden.github.io/powerline-veg-risk/reference/osm_buildings.md)
carry the same two.
