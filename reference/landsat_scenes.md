# Find Landsat Collection 2 Level-2 scenes over an area of interest

Searches the Microsoft Planetary Computer STAC API (no account or key
needed) for surface-reflectance scenes intersecting `aoi` in the given
years and months.

## Usage

``` r
landsat_scenes(
  aoi,
  years,
  months = 7:9,
  max_cloud = 50,
  platforms = c("landsat-8", "landsat-9"),
  stac_url = pc_stac
)
```

## Arguments

- aoi:

  An `sf`/`sfc` object (any CRS) or a `bbox`.

- years:

  Integer vector of calendar years.

- months:

  Integer vector of months (1-12) to keep.

- max_cloud:

  Maximum scene cloud cover (percent). Clouds over the corridor itself
  are masked per pixel later, so this only drops scenes that are mostly
  cloud.

- platforms:

  Landsat platforms to keep.

- stac_url:

  STAC API root.

## Value

A tibble with one row per scene: `id`, `datetime`, `platform`,
`cloud_cover`, and signed-on-read asset URLs `red`, `nir`, `swir1`,
`qa`.

## Details

Pick `months` for the local dry season, when canopy moisture matters for
fire (e.g. July-September on the Colorado Front Range, August-October in
Tennessee). Landsat 7 is excluded by default: its scan-line corrector
failed in 2003 and every later scene has missing stripes.
