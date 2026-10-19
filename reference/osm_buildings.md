# Fetch building footprints from OpenStreetMap

Only closed ways are returned; multipolygon relations (rare for houses)
are skipped.

## Usage

``` r
osm_buildings(aoi, overpass_url = "https://overpass-api.de/api/interpreter")
```

## Arguments

- aoi:

  An `sf`/`sfc` object or `bbox` defining the search window.

- overpass_url:

  Overpass endpoint.

## Value

An `sf` POLYGON data frame (EPSG:4326) with `osm_id`.
