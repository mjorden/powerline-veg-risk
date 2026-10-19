# vegrisk: LiDAR Vegetation Encroachment and Fall-In Risk for Power Line Corridors

Builds a vegetation-risk screen for overhead power lines from public
data: USGS 3DEP airborne LiDAR (LAS/LAZ) and OpenStreetMap
transmission-line geometry. Clips the point cloud to a line corridor,
height-normalises it, trains a random-forest point classifier on local
geometric (eigenvalue) features with spatially blocked cross-validation,
and summarises grow-in and fall-in ("strike tree") risk per line
segment. Optionally ranks the dry-season greenness (NDVI) and moisture
(NDMI) of grown-in canopy from Landsat Collection 2 surface reflectance,
and which strike trees historical fire-weather winds (ERA5) and the
National Weather Service forecast would throw into the line.

## See also

Useful links:

- <https://mjorden.github.io/powerline-veg-risk/>

- <https://github.com/mjorden/powerline-veg-risk>

- Report bugs at <https://github.com/mjorden/powerline-veg-risk/issues>

## Author

**Maintainer**: Matt Jorden <matthew.jorden@gmail.com>
