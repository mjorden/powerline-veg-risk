# Find USGS 3DEP LiDAR point-cloud tiles intersecting an area of interest

Queries The National Map (TNM) Access API for "Lidar Point Cloud (LPC)"
products whose footprint intersects `aoi`.

## Usage

``` r
tnm_lidar_tiles(aoi, project = NULL, max_items = 100)
```

## Arguments

- aoi:

  An `sf`/`sfc` object (any CRS) or a `bbox`.

- project:

  Optional regular expression matched against the tile title to keep a
  single acquisition (3DEP areas are often flown several times; mixing
  years in one model mixes vegetation states).

- max_items:

  Page size for the API.

## Value

An `sf` data frame of tiles (EPSG:4326 footprints) with columns `title`,
`url`, `size_mb`, `pub_date`.
