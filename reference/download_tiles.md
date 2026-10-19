# Download LiDAR tiles, skipping files already present

Download LiDAR tiles, skipping files already present

## Usage

``` r
download_tiles(tiles, dest_dir = "data-raw/laz")
```

## Arguments

- tiles:

  Output of
  [`tnm_lidar_tiles()`](https://mjorden.github.io/powerline-veg-risk/reference/tnm_lidar_tiles.md).

- dest_dir:

  Directory for the `.laz` files.

## Value

Character vector of local file paths.
