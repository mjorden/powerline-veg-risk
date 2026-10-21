# Download LiDAR tiles, skipping files already present

Each tile is downloaded to a `.part` file and renamed only once it is
complete, so an interrupted download is retried on the next run instead
of being accepted as a tile. Where TNM reported the size, the file is
checked against it, before and after the download.

## Usage

``` r
download_tiles(tiles, dest_dir = "data-raw/laz", timeout_s = 3600)
```

## Arguments

- tiles:

  Output of
  [`tnm_lidar_tiles()`](https://mjorden.github.io/powerline-veg-risk/reference/tnm_lidar_tiles.md).

- dest_dir:

  Directory for the `.laz` files.

- timeout_s:

  Timeout per tile download.

## Value

Character vector of local file paths.
