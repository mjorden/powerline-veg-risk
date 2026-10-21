# Median dry-season NDVI and NDMI composite from Landsat scenes

Reads only the window around `aoi` from each scene's cloud-optimised
GeoTIFFs, masks cloud, shadow, snow and water with
[`qa_clear()`](https://mjorden.github.io/powerline-veg-risk/reference/qa_clear.md),
converts to surface reflectance, and takes the per-pixel median over all
clear observations.

## Usage

``` r
landsat_composite(scenes, aoi, buffer_m = 100)
```

## Arguments

- scenes:

  Output of
  [`landsat_scenes()`](https://mjorden.github.io/powerline-veg-risk/reference/landsat_scenes.md).

- aoi:

  `sf`/`sfc` area to read (any CRS), normally the corridor.

- buffer_m:

  Extra margin read around `aoi`, in metres.

## Value

A `SpatRaster` on the Landsat 30 m grid (UTM) with layers `ndvi`, `ndmi`
and `n_obs` (clear observations per pixel). Attributes `scenes` (ids
used) and `dates` record what went into it; `scene_log` is a data frame
of every scene offered (`id`, `datetime`, `used`, `skip_reason`: `NA`
when used, `"no coverage"` when the scene misses the AOI, else the read
error), so a composite thinned by transient failures can be told from
one that used every scene.

## Details

- **NDVI** = (NIR - red) / (NIR + red): greenness / live leaf area.

- **NDMI** = (NIR - SWIR1) / (NIR + SWIR1): canopy water content, the
  closer of the two to fuel moisture.

Both are relative indicators. They are not fuel-moisture measurements
and have no fire-danger thresholds; compare pixels within one composite,
not across sites or seasons.
